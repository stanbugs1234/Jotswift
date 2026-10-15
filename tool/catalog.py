"""Checks and publishes catalog items (covers, papers, ...).

Each item lives in catalog/<id>/:
  listing.json   what it is and how it's offered (see docs/content.md)
  cover.webp     covers: the cover image, 1536 x 2048
  stickers.json  sticker packs: {"stickers": [{"file": "stickers/x.webp", "name": "X"}]}
  stickers/      sticker packs: transparent WebP images, at most 1024 px
  template.pdf   templates: the pages (make them with tool/make_planner.py)
  template.json  templates: {"mode": "notebook", "sections": [...]} or
                 {"mode": "pages", "pages": [...]}
  preview.webp   covers, sticker packs and templates: a small preview,
                 at most 512 px wide

Usage, from the repo root:
  python3 tool/catalog.py check [id ...]
  python3 tool/catalog.py publish <id> --testers | --public | --hidden | --retired [--dry-run]
  python3 tool/catalog.py set-tester <uid> on|off

publish and set-tester use your gcloud login (`gcloud auth login`) and
write past the security rules, as a server would. Needs Pillow.
"""

import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog"

KINDS = {"cover", "paper", "template", "stickers", "collection"}
VISIBILITIES = {"hidden", "testers", "public", "retired"}
PATTERNS = {"blank", "lined", "narrowLined", "grid", "dot", "music", "cornell"}
PRODUCT = re.compile(r"^(pack|bundle|planner)_[a-z0-9_]+$")
ID = re.compile(r"^[a-z0-9_]+$")
HEX = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

COVER_SIZE = (1536, 2048)
MAX_PREVIEW_WIDTH = 512
MAX_PACK_BYTES = {"template": 25 * 1024 * 1024}
DEFAULT_MAX_PACK_BYTES = 5 * 1024 * 1024

MAX_STICKER_SIZE = 1024


def pack_files(folder, kind):
    """The files of an item that go into its pack.zip, in a fixed order."""
    if kind == "cover":
        return ["cover.webp"]
    if kind == "template":
        return ["template.pdf", "template.json"]
    if kind == "stickers":
        images = sorted(
            f.relative_to(folder).as_posix() for f in (folder / "stickers").glob("*.webp")
        )
        return ["stickers.json", *images]
    return []


PACKED_KINDS = {"cover", "stickers", "template"}


def pdf_page_count(path):
    """Counts a PDF's pages (enough to check template.json against)."""
    return len(re.findall(rb"/Type\s*/Page(?![a-zA-Z])", path.read_bytes()))


def template_spec(folder):
    spec = json.loads((folder / "template.json").read_text())
    if spec.get("mode") == "notebook":
        pages = [p for s in spec.get("sections", []) for p in s.get("pages", [])]
    else:
        pages = spec.get("pages", [])
    return spec, pages


class CheckError(Exception):
    pass


def argb(hex_color):
    """'#RRGGBB' or '#AARRGGBB' to an ARGB int, as the app stores colors."""
    h = hex_color[1:]
    return int(h if len(h) == 8 else "FF" + h, 16)


def luminance(hex_color):
    v = argb(hex_color)
    channels = [((v >> s) & 0xFF) / 255 for s in (16, 8, 0)]
    lin = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def load(item_id):
    folder = CATALOG / item_id
    path = folder / "listing.json"
    if not path.exists():
        raise CheckError(f"{item_id}: no listing.json")
    try:
        return folder, json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise CheckError(f"{item_id}: listing.json is not valid JSON ({e})")


def check(item_id):
    """Returns the listing if the item is ready to publish; raises otherwise."""
    from PIL import Image

    folder, listing = load(item_id)
    problems = []

    def need(cond, message):
        if not cond:
            problems.append(message)

    need(ID.match(item_id), "id may only use a-z, 0-9 and _")
    need(listing.get("kind") in KINDS, f"kind must be one of {sorted(KINDS)}")
    need(isinstance(listing.get("name"), str) and listing["name"].strip(), "name is missing")
    need(isinstance(listing.get("version"), int) and listing["version"] >= 1, "version must be 1 or more")
    need(listing.get("visibility", "hidden") in VISIBILITIES, f"visibility must be one of {sorted(VISIBILITIES)}")

    unlock = listing.get("unlock", {})
    need(isinstance(unlock, dict), "unlock must be an object")
    products = unlock.get("products", []) if isinstance(unlock, dict) else []
    for p in products:
        need(isinstance(p, str) and PRODUCT.match(p), f"product id '{p}' must look like pack_<name>, bundle_<name> or planner_<name>")
    need(
        unlock.get("free") or unlock.get("pro") or products or listing.get("collectionId"),
        "unlock must say how to get it: free, pro, products or a collectionId",
    )

    kind = listing.get("kind")
    if kind == "cover":
        need(isinstance(listing.get("color"), str) and HEX.match(listing["color"]), "covers need a color like #RRGGBB (shown while loading)")
        cover = folder / "cover.webp"
        preview = folder / "preview.webp"
        need(cover.exists(), "cover.webp is missing")
        need(preview.exists(), "preview.webp is missing")
        if cover.exists():
            with Image.open(cover) as im:
                need(im.format == "WEBP", "cover.webp must be a WebP image")
                need(im.size == COVER_SIZE, f"cover.webp must be {COVER_SIZE[0]} x {COVER_SIZE[1]} (is {im.size[0]} x {im.size[1]})")
    elif kind == "stickers":
        need((folder / "preview.webp").exists(), "preview.webp is missing")
        listing_file = folder / "stickers.json"
        entries = []
        if not listing_file.exists():
            problems.append("stickers.json is missing")
        else:
            try:
                entries = json.loads(listing_file.read_text()).get("stickers", [])
            except (json.JSONDecodeError, AttributeError):
                problems.append("stickers.json must be {\"stickers\": [...]}")
        need(entries, "stickers.json lists no stickers")
        listed = set()
        for e in entries:
            file, name = e.get("file"), e.get("name")
            need(isinstance(name, str) and name.strip(), f"{file}: needs a name")
            path = folder / file if isinstance(file, str) else None
            if path is None or not path.exists() or not file.startswith("stickers/"):
                problems.append(f"{file}: not found in stickers/")
                continue
            listed.add(file)
            with Image.open(path) as im:
                need(im.format == "WEBP", f"{file}: must be a WebP image")
                need("A" in im.getbands(), f"{file}: needs a transparent background")
                need(max(im.size) <= MAX_STICKER_SIZE, f"{file}: at most {MAX_STICKER_SIZE} px")
        for f in (folder / "stickers").glob("*.webp") if (folder / "stickers").exists() else []:
            rel = f.relative_to(folder).as_posix()
            need(rel in listed, f"{rel}: not listed in stickers.json")
    elif kind == "template":
        need((folder / "preview.webp").exists(), "preview.webp is missing")
        pdf = folder / "template.pdf"
        if not pdf.exists() or not pdf.read_bytes().startswith(b"%PDF"):
            problems.append("template.pdf is missing or not a PDF")
        elif not (folder / "template.json").exists():
            problems.append("template.json is missing")
        else:
            try:
                spec, pages = template_spec(folder)
            except (json.JSONDecodeError, AttributeError):
                spec, pages = {}, []
                problems.append("template.json is not valid")
            need(spec.get("mode") in ("notebook", "pages"), 'template.json "mode" must be "notebook" or "pages"')
            need(pages, "template.json lists no pages")
            count = pdf_page_count(pdf)
            for p in pages:
                n = p.get("pdfPage") if isinstance(p, dict) else None
                need(isinstance(n, int) and 1 <= n <= count, f"pdfPage {n} is not a page of template.pdf ({count} pages)")
                need(isinstance(p, dict) and isinstance(p.get("title"), str), f"page {n} needs a title")
    elif kind == "paper":
        paper = listing.get("paper")
        if not isinstance(paper, dict):
            problems.append("papers need a paper object")
        else:
            for key in ("color", "lineColor"):
                need(isinstance(paper.get(key), str) and HEX.match(paper[key]), f"paper.{key} must be #RRGGBB")
            margin = paper.get("marginColor")
            need(margin is None or (isinstance(margin, str) and HEX.match(margin)), "paper.marginColor must be #RRGGBB or null")
            need(paper.get("pattern") in PATTERNS, f"paper.pattern must be one of {sorted(PATTERNS)}")
            spacing = paper.get("spacing")
            need(isinstance(spacing, (int, float)) and 8 <= spacing <= 200, "paper.spacing must be 8-200")
            if not problems:
                # Faint is good, invisible is not.
                need(contrast(paper["color"], paper["lineColor"]) >= 1.15, "paper.lineColor is too close to paper.color to see")
    elif kind == "collection":
        need((folder / "preview.webp").exists(), "preview.webp is missing")
        need(not listing.get("collectionId"), "a collection can't be inside another collection")

    collection_id = listing.get("collectionId")
    if collection_id:
        try:
            _, collection = load(collection_id)
            need(collection.get("kind") == "collection", f"collectionId '{collection_id}' is not a collection")
        except CheckError:
            problems.append(f"collectionId '{collection_id}' has no catalog/{collection_id}/listing.json")

    if kind in ("cover", "stickers", "template", "collection") and (folder / "preview.webp").exists():
        with Image.open(folder / "preview.webp") as im:
            need(im.format == "WEBP", "preview.webp must be a WebP image")
            need(im.size[0] <= MAX_PREVIEW_WIDTH, f"preview.webp must be at most {MAX_PREVIEW_WIDTH} px wide")

    if not problems and kind in PACKED_KINDS:
        size = len(build_pack(folder, kind))
        limit = MAX_PACK_BYTES.get(kind, DEFAULT_MAX_PACK_BYTES)
        need(size <= limit, f"pack is {size} bytes; the limit is {limit}")

    if problems:
        raise CheckError(f"{item_id}:\n  - " + "\n  - ".join(problems))
    return listing


def build_pack(folder, kind):
    """The item's pack.zip. Same files give the same bytes (and checksum)."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        for name in pack_files(folder, kind):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            z.writestr(info, (folder / name).read_bytes())
    return out.getvalue()


# Firebase (REST, with the gcloud login)


def project_id():
    return json.loads((ROOT / ".firebaserc").read_text())["projects"]["default"]


def token():
    return subprocess.run(
        ["gcloud", "auth", "print-access-token"], check=True, capture_output=True, text=True
    ).stdout.strip()


def request(method, url, body=None, content_type="application/json"):
    headers = {"Authorization": f"Bearer {token()}", "x-goog-user-project": project_id()}
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as res:
            text = res.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        sys.exit(f"{method} {url} failed ({e.code}): {e.read().decode()[:500]}")


def firestore_url(path):
    return (
        f"https://firestore.googleapis.com/v1/projects/{project_id()}"
        f"/databases/(default)/documents/{path}"
    )


def to_value(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_value(x) for k, x in v.items()}}}
    raise TypeError(f"can't store {v!r}")


def upload(path, data, content_type):
    bucket = f"{project_id()}.firebasestorage.app"
    url = (
        f"https://storage.googleapis.com/upload/storage/v1/b/{bucket}/o"
        f"?uploadType=media&name={urllib.parse.quote(path, safe='')}"
    )
    request("POST", url, data, content_type)


def unlock_of(listing):
    """How an item unlocks. An item in a collection also unlocks with the
    collection's products (and with Pro if the collection is in Pro), so
    the app and the Storage rules only ever look at the item itself.
    Republish a collection's items after changing its products."""
    own = listing.get("unlock", {})
    unlock = {
        "free": bool(own.get("free")),
        "pro": bool(own.get("pro")),
        "products": list(own.get("products", [])),
    }
    if listing.get("collectionId"):
        _, collection = load(listing["collectionId"])
        theirs = collection.get("unlock", {})
        unlock["pro"] = unlock["pro"] or bool(theirs.get("pro"))
        for p in theirs.get("products", []):
            if p not in unlock["products"]:
                unlock["products"].append(p)
    return unlock


def publish(item_id, visibility, dry_run):
    listing = check(item_id)
    folder = CATALOG / item_id
    kind = listing["kind"]
    version = listing["version"]

    doc = {
        "kind": kind,
        "name": listing["name"],
        "version": version,
        "format": listing.get("format", 1),
        "unlock": unlock_of(listing),
        "visibility": visibility,
        "category": listing.get("category"),
        "tags": listing.get("tags", []),
    }
    if listing.get("collectionId"):
        doc["collectionId"] = listing["collectionId"]
    if kind == "cover":
        doc["color"] = argb(listing["color"])
    if kind == "template":
        spec, pages = template_spec(folder)
        doc["templateMode"] = spec["mode"]
        doc["pageCount"] = len(pages)
    if kind == "paper":
        p = listing["paper"]
        doc["paper"] = {
            "color": argb(p["color"]),
            "lineColor": argb(p["lineColor"]),
            "marginColor": argb(p["marginColor"]) if p.get("marginColor") else None,
            "pattern": p["pattern"],
            "spacing": float(p["spacing"]),
        }

    uploads = []
    if kind == "collection":
        preview = f"catalog/{item_id}/{version}/preview.webp"
        doc["files"] = {"preview": preview}
        uploads = [(preview, (folder / "preview.webp").read_bytes(), "image/webp")]
    if kind in PACKED_KINDS:
        pack = build_pack(folder, kind)
        base = f"catalog/{item_id}/{version}"
        doc["files"] = {
            "pack": f"{base}/pack.zip",
            "sha256": hashlib.sha256(pack).hexdigest(),
            "bytes": len(pack),
            "preview": f"{base}/preview.webp",
        }
        uploads = [
            (f"{base}/pack.zip", pack, "application/zip"),
            (f"{base}/preview.webp", (folder / "preview.webp").read_bytes(), "image/webp"),
        ]

    existing = request("GET", firestore_url(f"catalog/{item_id}")) if not dry_run else None
    if existing:
        fields = existing.get("fields", {})
        old_version = int(fields.get("version", {}).get("integerValue", 0))
        old_sha = fields.get("files", {}).get("mapValue", {}).get("fields", {}).get("sha256", {}).get("stringValue")
        if version < old_version:
            sys.exit(f"{item_id}: version {version} is older than the published {old_version}")
        if version == old_version and old_sha and old_sha != doc.get("files", {}).get("sha256"):
            sys.exit(f"{item_id}: the files changed; bump version in listing.json first")

    print(f"{item_id}: {kind} v{version}, {visibility}")
    for path, data, _ in uploads:
        print(f"  upload {path} ({len(data)} bytes)")
    print(f"  write catalog/{item_id}")
    if dry_run:
        print("  (dry run: nothing was changed)")
        return
    for path, data, content_type in uploads:
        upload(path, data, content_type)
    request("PATCH", firestore_url(f"catalog/{item_id}"), {"fields": {k: to_value(v) for k, v in doc.items()}})
    print("  done")


def set_tester(uid, on):
    url = firestore_url(f"users/{uid}") + "?updateMask.fieldPaths=tester"
    request("PATCH", url, {"fields": {"tester": to_value(on)}})
    print(f"{uid}: tester {'on' if on else 'off'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("check", help="check items (all by default)")
    c.add_argument("ids", nargs="*")
    p = sub.add_parser("publish", help="upload an item and write its listing")
    p.add_argument("id")
    who = p.add_mutually_exclusive_group(required=True)
    who.add_argument("--testers", action="store_true", help="only accounts marked as testers see it")
    who.add_argument("--public", action="store_true", help="everyone sees it")
    who.add_argument("--hidden", action="store_true", help="nobody sees it")
    who.add_argument("--retired", action="store_true", help="no longer offered; notebooks using it keep it")
    p.add_argument("--dry-run", action="store_true")
    t = sub.add_parser("set-tester", help="mark an account as a tester")
    t.add_argument("uid")
    t.add_argument("state", choices=["on", "off"])
    args = parser.parse_args()

    if args.command == "check":
        everything = sorted(d.name for d in CATALOG.iterdir() if d.is_dir()) if CATALOG.exists() else []
        ids = args.ids or everything
        failed = 0
        for item_id in ids:
            try:
                check(item_id)
                print(f"ok    {item_id}")
            except CheckError as e:
                failed += 1
                print(f"FAIL  {e}")
        print(f"{len(ids) - failed} of {len(ids)} items are ready.")
        sys.exit(1 if failed else 0)
    elif args.command == "publish":
        try:
            visibility = next(v for v in ("testers", "public", "hidden", "retired") if getattr(args, v))
            publish(args.id, visibility, args.dry_run)
        except CheckError as e:
            sys.exit(f"Not published.\n{e}")
    else:
        set_tester(args.uid, args.state == "on")


if __name__ == "__main__":
    main()
