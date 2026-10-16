"""Makes the spread planners listed in tool/spreads.json: undated,
landscape two-page spreads with rainbow tabs that link to each section,
in three colourways (Classic, Pastel, Neutral).

  python3 tool/make_spreads.py spread_notes    # one planner
  python3 tool/make_spreads.py all
  python3 tool/make_spreads.py --list

Each planner becomes catalog/<id>/ with template.pdf (Classic),
template_pastel.pdf, template_neutral.pdf, template.json (sections and
the colourways as "variants"), preview.webp and listing.json. Re-running
keeps each item's version; raise it by hand when pages change.

A planner in spreads.json:
  "spread_weekly": {
    "name": "Weekly Planner", "price": "2.99",
    "unlock": {"pro": true, "products": ["planner_spread_weekly"]},
    "tags": ["weekly", "undated"],
    "sections": [
      {"tab": "Months", "title": "Months",
       "pages": [{"layout": "dated.month", "repeat": 12, "title": "Month {n}"}]},
      {"tab": "Weeks", "pages": [{"layout": "dated.week", "repeat": 52}]}]}

Every planner starts with an index page that links to each section. A
section of more than one page starts with a Contents page linking each of
its pages, and each page's header steps through its section.
"""

import inspect
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_planner as mp  # noqa: E402
import spreads  # noqa: E402
from spreads.kit import S, caps, panel  # noqa: E402
from planner_nav import chevron  # noqa: E402
from spreads.look import BOTTOM, COLOURWAYS, TOP, Spread, draw_frame, new_page  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PLANNERS = json.loads((ROOT / "tool" / "spreads.json").read_text())["planners"]


CONTENTS = "contents"


def plan(planner):
    """The pages in order: (section, tab, layout, n, title). Page 0 is the
    index; a section of several pages starts with its Contents page."""
    entries = [("Index", "Index", None, 1, "Index")]
    for section in planner["sections"]:
        tab = section["tab"]
        title = section.get("title", tab)
        pages = []
        for entry in section["pages"]:
            if isinstance(entry, str):
                entry = {"layout": entry}
            make, default = spreads.get(entry["layout"])
            for n in range(1, entry.get("repeat", 1) + 1):
                name = entry.get("title", default)
                pages.append((title, tab, make, n, name.format(n=n)))
        if len(pages) > 1:
            entries.append((title, tab, CONTENTS, 1, "Contents"))
        entries += pages
    return entries


def contents_page(sp, entries, first, colour):
    """Every page of the section starting at [first], linked, in rows
    across both halves."""
    p = sp.page
    tab = entries[first][1]
    items = [(i, e[4]) for i, e in enumerate(entries) if e[1] == tab and e[2] is not CONTENTS]
    per_half = (len(items) + 1) // 2
    cols = 1 if per_half <= 16 else 2
    rows = (per_half + cols - 1) // cols
    for half, (x0, x1) in enumerate((sp.left, sp.right)):
        chunk = items[half * per_half:(half + 1) * per_half]
        if not chunk:
            continue
        title = f"{tab}: tap a page" if half == 0 else "More pages"
        top = panel(p, x0, TOP - 4, x1 - x0, TOP - BOTTOM - 8, title)
        cw = (x1 - x0 - 20) / cols
        rh = min(30, (top - BOTTOM - 16) / rows)
        for k, (page, name) in enumerate(chunk):
            c, r = divmod(k, rows)
            x, y = x0 + 10 + c * cw, top - 14 - (r + 1) * rh
            p.rect(x, y + rh / 2 - 6, 12, 12, fill=colour)
            p.text(x + 20, y + rh / 2 - 3.5, name, 10, rgb=S().ink, bold=True)
            chevron(p, x + cw - 12, y + rh / 2, 7, S().soft)
            p.line(x, y, x + cw - 6, y, rgb=S().rule, width=0.5)
            p.link(x - 4, y, cw, rh, page)


def index_page(sp, planner, entries, tabs):
    """Contents: each section with its colour, linked."""
    p = sp.page
    colours = draw_index_colours = sp.colourway.tabs
    sections = [t for t in tabs if t[0] != "Index"]
    half = (len(sections) + 1) // 2
    for col, (x0, x1) in enumerate((sp.left, sp.right)):
        title = "Contents" if col == 0 else ("More" if len(sections) > half else "How to use it")
        top = panel(p, x0, TOP - 4, x1 - x0, TOP - BOTTOM - 8, title)
        for i, (label, target) in enumerate(sections[col * half:(col + 1) * half]):
            y = top - 26 - i * 34
            k = tabs.index((label, target))
            p.rect(x0 + 10, y - 4, 18, 18, fill=colours[k % len(colours)])
            count = sum(1 for e in entries if e[1] == label and e[2] is not CONTENTS)
            p.text(x0 + 38, y + 4, label, 12, rgb=S().ink, bold=True)
            p.text(x1 - 10, y + 4, f"{count} page{'s' if count != 1 else ''}", 8, rgb=S().soft, right=True)
            p.line(x0 + 10, y - 9, x1 - 10, y - 9, rgb=S().rule, width=0.5)
            p.link(x0 + 6, y - 8, x1 - x0 - 12, 28, target)
    _ = draw_index_colours
    if len(sections) <= half:
        x0, x1 = sp.right
        tips = [
            "Tap a tab on the right to jump to that section.",
            "Tap  < INDEX  at the top of any page to come back here.",
            "It's undated: write in your own months, weeks and days.",
            "Pages repeat, so the planner works for any year.",
            "Add stickers, photos and text boxes from the toolbar.",
        ]
        for i, tip in enumerate(tips):
            p.text(x0 + 10, TOP - 46 - i * 22, tip, 9.5, rgb=S().ink)
    caps(p, sp.left[0], BOTTOM + 4, f"{planner['name']}  ·  undated: write in your own dates", 6.5,
         rgb=S().soft)


def build(planner, colourway):
    entries = plan(planner)
    firsts = {}
    for i, e in enumerate(entries):
        firsts.setdefault(e[1], i)
    tabs = list(firsts.items())
    pages = []
    for i, (section, tab, make, n, title) in enumerate(entries):
        p = new_page(colourway)
        sp = Spread(p, planner.get("short", planner["name"]), tab, title, tabs, 0 if i else None)
        sp.colourway = colourway
        siblings = [k for k, e in enumerate(entries) if e[1] == tab and e[2] is not CONTENTS]
        if make not in (None, CONTENTS) and len(siblings) > 1:
            at = siblings.index(i)
            sp.steps = (siblings[at - 1] if at else None, firsts[tab], at + 1, len(siblings),
                        siblings[at + 1] if at + 1 < len(siblings) else None)
        draw_frame(sp, colourway)
        if make is None:
            index_page(sp, planner, entries, tabs)
        elif make is CONTENTS:
            contents_page(sp, entries, i, colourway.tabs[[t for t, _ in tabs].index(tab) % len(colourway.tabs)])
        else:
            make(sp, n) if len(inspect.signature(make).parameters) > 1 else make(sp)
        pages.append(p)
    return pages, entries


def spec(entries):
    sections = []
    for i, (section, tab, _, _, title) in enumerate(entries):
        if not sections or sections[-1]["title"] != section:
            sections.append({"title": section, "pages": []})
        sections[-1]["pages"].append({"pdfPage": i + 1, "title": title})
    return {
        "mode": "notebook",
        "sections": sections,
        "variants": [
            {"name": c.name, "file": c.file,
             "color": "#%02X%02X%02X" % tuple(round(v * 255) for v in c.style.accent)}
            for c in COLOURWAYS
        ],
    }


def write(pid):
    planner = PLANNERS[pid]
    folder = ROOT / "catalog" / pid
    folder.mkdir(parents=True, exist_ok=True)
    count = 0
    for c in COLOURWAYS:
        pages, entries = build(planner, c)
        mp.write_pdf(pages, folder / c.file)
        count = len(pages)
    (folder / "template.json").write_text(json.dumps(spec(entries), indent=2) + "\n")
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")
    listing = {
        "kind": "template",
        "name": planner["name"],
        "version": 1,
        "unlock": planner["unlock"],
        "category": "spreads",
        "tags": planner.get("tags", []),
    }
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")
    mp.use_size(612, 792)
    return count


def main():
    args = sys.argv[1:]
    if args == ["--list"]:
        for pid, p in PLANNERS.items():
            price = "free" if p["unlock"].get("free") else f"${p['price']}"
            print(f"{pid:28} {price:6} {p['name']}")
        return
    if len(args) != 1 or (args[0] != "all" and args[0] not in PLANNERS):
        sys.exit(__doc__)
    for pid in PLANNERS if args[0] == "all" else args:
        print(f"{pid}: {write(pid)} spreads x {len(COLOURWAYS)} colourways")


if __name__ == "__main__":
    main()
