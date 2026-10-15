"""Makes the page packs and journals listed in tool/packs.json, drawn in
code in Jotswift's plain style.

  python3 tool/make_pack.py student_pages   # one pack
  python3 tool/make_pack.py all             # every pack
  python3 tool/make_pack.py --list          # ids, prices and page counts

Each pack becomes catalog/<id>/ with template.pdf, template.json,
preview.webp and listing.json. Re-running keeps each item's version, so
raise "version" in its listing.json by hand when its pages change, then
check and publish with tool/catalog.py. Needs Pillow, and macOS `sips` for
the preview.

A pack in packs.json:
  "student_pages": {
    "name": "Student pack", "category": "study", "tags": ["school"],
    "unlock": {"pro": true, "products": ["pack_student"]},
    "price": "1.99",                 // US dollars, for docs/pricing.md
    "mode": "pages",                 // or "notebook" for journals
    "pages": ["study.lecture_notes", // a layout (see tool/layouts/)
              {"layout": "journal.day", "repeat": 90,
               "title": "Day {n}", "section": "Days"}]
  }
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import layouts  # noqa: E402
import make_planner as mp  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PACKS = json.loads((ROOT / "tool" / "packs.json").read_text())["packs"]


def build(pack):
    """The pages and template.json for [pack]."""
    mp.use_style(mp.DEFAULT)
    pages, sections = [], []
    for entry in pack["pages"]:
        if isinstance(entry, str):
            entry = {"layout": entry}
        make = layouts.get(entry["layout"])
        for n in range(1, entry.get("repeat", 1) + 1):
            page, title = make()
            pages.append(page)
            if "title" in entry:
                title = entry["title"].format(n=n)
            section = entry.get("section", "Pages")
            if not sections or sections[-1]["title"] != section:
                sections.append({"title": section, "pages": []})
            sections[-1]["pages"].append({"pdfPage": len(pages), "title": title})
    if pack.get("mode", "pages") == "notebook":
        spec = {"mode": "notebook", "sections": sections}
    else:
        spec = {"mode": "pages", "pages": [pg for sec in sections for pg in sec["pages"]]}
    return pages, spec


def write(pack_id):
    pack = PACKS[pack_id]
    folder = ROOT / "catalog" / pack_id
    folder.mkdir(parents=True, exist_ok=True)
    pages, spec = build(pack)
    mp.write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec, indent=2) + "\n")
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")
    listing = {
        "kind": "template",
        "name": pack["name"],
        "version": 1,
        "unlock": pack["unlock"],
        "category": pack["category"],
        "tags": pack.get("tags", []),
    }
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")
    return len(pages)


def main():
    args = sys.argv[1:]
    if args == ["--list"]:
        for pid, pack in PACKS.items():
            price = "free" if pack["unlock"].get("free") else f"${pack['price']}"
            print(f"{pid:28} {price:6} {pack['name']}")
        return
    if len(args) != 1 or (args[0] != "all" and args[0] not in PACKS):
        sys.exit(__doc__)
    for pid in PACKS if args[0] == "all" else args:
        print(f"{pid}: {write(pid)} pages")


if __name__ == "__main__":
    main()
