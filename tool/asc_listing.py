#!/usr/bin/env python3
"""Fills in the App Store listing for the version being prepared, from
docs/app-store-listing.md: name, subtitle, privacy URL, categories, age
rating, description, keywords, promotional text, support URL, copyright
and the review notes.

Usage, from the repo root:
  python3 tool/asc_listing.py

Uses the App Store Connect API key the TestFlight script uses. Nothing is
public until the version is submitted, and every field stays editable.
Screenshots, the App Privacy answers and the review contact are done by
hand in App Store Connect.
"""
import re
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_products as a  # noqa: E402

APP_ID = "6823230637"
SUPPORT = "https://notely-b1aec.web.app/support.html"
PRIVACY = "https://notely-b1aec.web.app/privacy.html"
DOC = (a.ROOT / "docs" / "app-store-listing.md").read_text()

# Age rating questions answered yes/no; the rest are NONE, INFREQUENT_OR_MILD
# or FREQUENT_OR_INTENSE. Jotswift answers no and NONE to all of them (4+).
AGE_BOOLEANS = {
    "advertising", "gambling", "lootBox", "healthOrWellnessTopics", "messagingAndChat",
    "parentalControls", "ageAssurance", "socialMedia", "unrestrictedWebAccess",
    "userGeneratedContent",
}
AGE_SKIP = {
    "kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
    "gracRatingClassificationNumber", "developerAgeRatingInfoUrl", "socialMediaAgeRestricted",
}


def block(heading):
    """The first ``` block after [heading]."""
    i = DOC.index(heading)
    return re.search(r"```\n(.*?)```", DOC[i:], re.S).group(1).strip()


def field(name):
    """A value from the App information table."""
    return re.search(rf"^\| {re.escape(name)} \| (.+?) \|$", DOC, re.M).group(1)


def paragraph(heading):
    """The first paragraph after [heading], on one line."""
    i = DOC.index(heading) + len(heading)
    return " ".join(DOC[i:].strip().split("\n\n")[0].split())


def patch(api, kind, id_, attributes=None, relationships=None):
    data = {"type": kind, "id": id_}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    api.call("PATCH", f"/v1/{kind}/{id_}", {"data": data})


def main():
    description = block("## Description")
    keywords = block("## Keywords")
    promo = paragraph("## Promotional text (170)")
    notes = block("## App Review notes")
    if len(description) > 4000 or len(keywords) > 100 or len(promo) > 170:
        sys.exit(f"Too long: description {len(description)}, keywords {len(keywords)}, "
                 f"promotional text {len(promo)}")

    api = a.Api()
    info = api.call("GET", f"/v1/apps/{APP_ID}/appInfos")["data"][0]
    loc = api.call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"][0]
    patch(api, "appInfoLocalizations", loc["id"], {
        "name": field("Name (30)"),
        "subtitle": field("Subtitle (30)"),
        "privacyPolicyUrl": PRIVACY,
    })
    print("Name, subtitle and privacy URL")

    patch(api, "appInfos", info["id"], relationships={
        "primaryCategory": a.rel("appCategories", "PRODUCTIVITY"),
        "secondaryCategory": a.rel("appCategories", "LIFESTYLE"),
    })
    print("Categories: Productivity, Lifestyle")

    decl = api.call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    patch(api, "ageRatingDeclarations", decl["id"], {
        k: (False if k in AGE_BOOLEANS else "NONE")
        for k in decl["attributes"] if k not in AGE_SKIP
    })
    print("Age rating: none of the above")

    version = next(
        v for v in api.call("GET", f"/v1/apps/{APP_ID}/appStoreVersions")["data"]
        if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"
    )
    patch(api, "appStoreVersions", version["id"], {"copyright": "2026 Jotswift"})
    vloc = api.call(
        "GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"][0]
    patch(api, "appStoreVersionLocalizations", vloc["id"], {
        "description": description,
        "keywords": keywords,
        "promotionalText": promo,
        "supportUrl": SUPPORT,
    })
    print(f"Version {version['attributes']['versionString']}: description, keywords, "
          "promotional text, support URL, copyright")

    review = api.call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]
    attributes = {"notes": notes, "demoAccountRequired": False}
    if review and review["attributes"].get("notes") == notes:
        print("Review notes: unchanged")
        return
    if review:
        # Apple asks for the whole contact again with any change; keep the
        # one typed in App Store Connect.
        contact = {k: v for k, v in review["attributes"].items() if k.startswith("contact") and v}
        if len(contact) < 4:
            sys.exit("Review notes not updated: add the review contact (name, email, phone) "
                     "in App Store Connect first.")
        patch(api, "appStoreReviewDetails", review["id"], {**attributes, **contact})
    else:
        api.create("appStoreReviewDetails", attributes,
                   {"appStoreVersion": a.rel("appStoreVersions", version["id"])})
    print("Review notes")


if __name__ == "__main__":
    main()
