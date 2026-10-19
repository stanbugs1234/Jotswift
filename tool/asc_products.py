"""Creates the store's products in App Store Connect with its API, so they
aren't typed in by hand: the Jotswift Pro subscriptions, Pro lifetime, and
the paid templates, each with its US price from tool/pricing.py.

  python3 tool/asc_products.py check            # what exists, what's missing
  python3 tool/asc_products.py create           # makes the launch products
  python3 tool/asc_products.py create --all     # every product in pricing.md

`check` only reads. `create` skips anything that already exists, so it can
be run again after a failure. It uses the same API key as
tool/release_testflight.sh.

The launch products are Pro (monthly, yearly, lifetime), the bestseller
planners and the bundles; everything else is included in Pro and can follow
later with --all.

Still done by hand in App Store Connect afterwards: a review screenshot for
each product (Apple needs one before review), and submitting the first
products together with an app version.
"""

import argparse
import sys
import time
from pathlib import Path

import jwt
import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

import pricing  # noqa: E402


def _release_setting(name):
    """A setting from tool/release_testflight.sh, so the key is named once."""
    for line in (ROOT / "tool" / "release_testflight.sh").read_text().splitlines():
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip('"')
    sys.exit(f"{name} not found in tool/release_testflight.sh")


KEY_ID = _release_setting("ASC_KEY_ID")
ISSUER_ID = _release_setting("ASC_ISSUER_ID")
KEY =Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"
BUNDLE_ID = "com.notelyapp.notely"
API = "https://api.appstoreconnect.apple.com"

GROUP = "Jotswift Pro"
FAMILY_SHARING = True  # Apple doesn't let this be turned off later
LAUNCH_SECTIONS = ("Bestseller planners", "Bundles")
PRO_TEXT = "Unlimited notebooks and every Pro template"
DESCRIPTIONS = {
    "Bestseller planners": "A linked digital planner for Jotswift",
    "Bundles": "A bundle of Jotswift templates",
    "Diaries & planners": "A linked digital planner for Jotswift",
    "Collections": "Planner, pages, covers, papers, stickers",
}
SUBSCRIPTIONS = {
    "pro_yearly": ("ONE_YEAR", 1),
    "pro_monthly": ("ONE_MONTH", 2),
}


class Api:
    def __init__(self):
        if not KEY.exists():
            sys.exit(f"Missing App Store Connect API key at {KEY}")
        self.key = KEY.read_text()
        self.session = requests.Session()
        self.token_at = 0

    def _auth(self):
        if time.time() - self.token_at > 600:
            now = int(time.time())
            token = jwt.encode(
                {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                self.key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
            self.session.headers["Authorization"] = f"Bearer {token}"
            self.token_at = time.time()

    def call(self, method, path, body=None, params=None):
        self._auth()
        r = self.session.request(method, API + path, json=body, params=params, timeout=60)
        if r.status_code >= 400:
            errors = r.json().get("errors", [{}]) if r.content else [{}]
            detail = "; ".join(e.get("detail") or e.get("title", "") for e in errors)
            raise RuntimeError(f"{method} {path}: {r.status_code} {detail}")
        return r.json() if r.content else {}

    def all(self, path, params=None):
        """Every item of a list, following its pages."""
        params = {"limit": 200, **(params or {})}
        out, url = [], path
        while url:
            page = self.call("GET", url, params=params)
            out += page["data"]
            nxt = page.get("links", {}).get("next")
            url, params = (nxt.removeprefix(API), None) if nxt else (None, None)
        return out

    def create(self, kind, attributes, relationships, included=None):
        body = {"data": {"type": kind, "attributes": attributes, "relationships": relationships}}
        if included:
            body["included"] = included
        return self.call("POST", f"/v1/{kind}" if kind != "inAppPurchases" else "/v2/inAppPurchases",
                         body)["data"]


def rel(kind, id_):
    return {"data": {"type": kind, "id": id_}}


def short(text, limit):
    """[text] cut at a word to fit Apple's [limit]."""
    text = text.split(" (")[0] if len(text) > limit else text
    while len(text) > limit:
        text = text.rsplit(" ", 1)[0]
    return text


def wanted(every):
    """(product id, name, kind, US price, description) for each product to make."""
    out = []
    for pid, name, kind, price in pricing.PRO:
        out.append((pid, name, "sub" if pid in SUBSCRIPTIONS else "once", price.split(" ")[0], PRO_TEXT))
    for section, pid, name, _, price in pricing.rows():
        if every or section in LAUNCH_SECTIONS:
            out.append((pid, name, "once", price,
                        DESCRIPTIONS.get(section, f"{section} for Jotswift")))
    return out


def existing(api, app):
    iaps = {i["attributes"]["productId"]: i for i in api.all(f"/v1/apps/{app}/inAppPurchasesV2")}
    groups = api.all(f"/v1/apps/{app}/subscriptionGroups")
    subs = {}
    for g in groups:
        for s in api.all(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            subs[s["attributes"]["productId"]] = s
    return groups, iaps, subs


def price_point(api, path, price):
    points = api.all(path, {"filter[territory]": "USA", "include": "territory"})
    for p in points:
        if p["attributes"]["customerPrice"] == price:
            return p["id"]
    raise RuntimeError(f"No US price point of ${price} at {path}")


def make_iap(api, app, territories, pid, name, price, description):
    iap = api.create("inAppPurchases", {
        "name": short(name, 64), "productId": pid, "inAppPurchaseType": "NON_CONSUMABLE",
        "familySharable": FAMILY_SHARING,
    }, {"app": rel("apps", app)})
    api.create("inAppPurchaseLocalizations", {
        "locale": "en-US", "name": short(name, 30), "description": description,
    }, {"inAppPurchaseV2": rel("inAppPurchases", iap["id"])})
    point = price_point(api, f"/v2/inAppPurchases/{iap['id']}/pricePoints", price)
    # Apple sets the other countries' prices from the US one.
    api.create("inAppPurchasePriceSchedules", {}, {
        "inAppPurchase": rel("inAppPurchases", iap["id"]),
        "baseTerritory": rel("territories", "USA"),
        "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${us}"}]},
    }, [{"type": "inAppPurchasePrices", "id": "${us}", "attributes": {"startDate": None},
         "relationships": {"inAppPurchasePricePoint": rel("inAppPurchasePricePoints", point)}}])
    api.create("inAppPurchaseAvailabilities", {"availableInNewTerritories": True}, {
        "inAppPurchase": rel("inAppPurchases", iap["id"]),
        "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
    })


def make_subscription(api, group, territories, pid, name, price, description):
    period, level = SUBSCRIPTIONS[pid]
    sub = api.create("subscriptions", {
        "name": short(name, 64), "productId": pid, "subscriptionPeriod": period,
        "familySharable": FAMILY_SHARING, "groupLevel": level,
    }, {"group": rel("subscriptionGroups", group)})
    api.create("subscriptionLocalizations", {
        "locale": "en-US", "name": short(name.split(" (")[0], 30), "description": description,
    }, {"subscription": rel("subscriptions", sub["id"])})
    api.create("subscriptionAvailabilities", {"availableInNewTerritories": True}, {
        "subscription": rel("subscriptions", sub["id"]),
        "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
    })
    us = price_point(api, f"/v1/subscriptions/{sub['id']}/pricePoints", price)
    # The US price, and Apple's equal price in every other country.
    points = [us] + [p["id"] for p in api.all(f"/v1/subscriptionPricePoints/{us}/equalizations")]
    for point in points:
        api.create("subscriptionPrices", {"startDate": None, "preserveCurrentPrice": False}, {
            "subscription": rel("subscriptions", sub["id"]),
            "subscriptionPricePoint": rel("subscriptionPricePoints", point),
        })
    if pid == "pro_yearly":
        for t in territories:  # one week free, everywhere
            api.create("subscriptionIntroductoryOffers", {
                "duration": "ONE_WEEK", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1,
            }, {"subscription": rel("subscriptions", sub["id"]), "territory": rel("territories", t)})


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["check", "create"])
    parser.add_argument("--all", action="store_true", help="every product, not just the launch ones")
    args = parser.parse_args()

    api = Api()
    apps = api.call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No app with bundle id {BUNDLE_ID} in App Store Connect.")
    app = apps[0]["id"]
    groups, iaps, subs = existing(api, app)
    want = wanted(args.all)
    missing = [w for w in want if w[0] not in iaps and w[0] not in subs]

    print(f"App {apps[0]['attributes']['name']} ({app})")
    for pid, name, kind, price, _ in want:
        have = iaps.get(pid) or subs.get(pid)
        state = have["attributes"].get("state", "?") if have else "missing"
        print(f"  {pid:34} ${price:>6}  {state}")
    print(f"{len(want) - len(missing)} of {len(want)} exist; {len(missing)} missing.")
    if args.command == "check" or not missing:
        return

    territories = [t["id"] for t in api.all("/v1/territories")]
    group = next((g["id"] for g in groups if g["attributes"]["referenceName"] == GROUP), None)
    if group is None and any(w[2] == "sub" for w in missing):
        group = api.create("subscriptionGroups", {"referenceName": GROUP}, {"app": rel("apps", app)})["id"]
        api.create("subscriptionGroupLocalizations", {"locale": "en-US", "name": GROUP},
                   {"subscriptionGroup": rel("subscriptionGroups", group)})
        print(f"Made subscription group {GROUP}")
    failed = []
    for pid, name, kind, price, description in missing:
        try:
            if kind == "sub":
                make_subscription(api, group, territories, pid, name, price, description)
            else:
                make_iap(api, app, territories, pid, name, price, description)
            print(f"Made {pid} (${price})")
        except RuntimeError as e:
            failed.append(pid)
            print(f"FAILED {pid}: {e}")
    if failed:
        sys.exit(f"{len(failed)} failed; fix the cause and run again (made ones are skipped).")


if __name__ == "__main__":
    main()
