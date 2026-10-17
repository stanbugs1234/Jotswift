"""Checks the links in Jotswift's template PDFs.

  python3 tool/check_links.py catalog/planner_2027 [more folders...]
  python3 tool/check_links.py --all      # every catalog folder with links

For every template it checks that each link points at a real page and
that every page can be reached from the first. Linked planners (with a
Home page, made by planner_nav) must also:

  - link every page but Home back to Home in one tap;
  - reach every page from Home in three taps or fewer;
  - link every day page from its month and from the year.

Reads the PDFs as tool/make_planner.py writes them (one object per
annotation, uncompressed); exits non-zero on any problem.
"""

import json
import re
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_OBJ = re.compile(rb"(\d+) 0 obj\n(.*?)\nendobj", re.S)
_KIDS = re.compile(rb"/Kids \[([^\]]*)\]")
_ANNOTS = re.compile(rb"/Annots \[([^\]]*)\]")
_DEST = re.compile(rb"/Dest \[(\d+) 0 R")


def links(pdf):
    """For each page (0-based), the set of pages its links open."""
    objs = {int(m.group(1)): m.group(2) for m in _OBJ.finditer(pdf.read_bytes())}
    pages_obj = next(body for body in objs.values() if b"/Type /Pages" in body)
    kids = [int(k) for k in re.findall(rb"(\d+) 0 R", _KIDS.search(pages_obj).group(1))]
    index = {pid: i for i, pid in enumerate(kids)}
    out = []
    for pid in kids:
        targets = set()
        annots = _ANNOTS.search(objs[pid])
        for aid in re.findall(rb"(\d+) 0 R", annots.group(1) if annots else b""):
            dest = _DEST.search(objs[int(aid)])
            if dest:
                target = index.get(int(dest.group(1)))
                if target is None:
                    raise ValueError(f"page {index[pid] + 1}: link to a missing page")
                targets.add(target)
        out.append(targets)
    return out


def depths(graph, start=0):
    seen = {start: 0}
    queue = deque([start])
    while queue:
        page = queue.popleft()
        for target in graph[page]:
            if target not in seen:
                seen[target] = seen[page] + 1
                queue.append(target)
    return seen


def check_book(pdf, spec, graph, reach):
    """Planners built by planner_kit (their spec lists "groups"): Home in
    one tap from every page, everything within three taps of Home, and
    every day linked from its month's calendar and its week."""
    problems = []
    pages = [p for s in spec["sections"] for p in s["pages"]]
    no_home = [i + 1 for i, targets in enumerate(graph) if i and 0 not in targets]
    if no_home:
        problems.append(f"{pdf.name}: {len(no_home)} pages don't link Home, e.g. {no_home[:5]}")
    deep = [i + 1 for i, d in reach.items() if d > 3]
    if deep:
        problems.append(f"{pdf.name}: {len(deep)} pages are over 3 taps from Home, e.g. {deep[:5]}")
    import datetime as dt

    span = {}
    for p in pages:
        if p.get("from"):
            a, b = dt.date.fromisoformat(p["from"]), dt.date.fromisoformat(p.get("to", p["from"]))
            span[p["pdfPage"] - 1] = (a, b)
    days = [(i, a) for i, (a, b) in span.items() if a == b]
    weeks = [(i, a, b) for i, (a, b) in span.items() if (b - a).days == 6]
    months = [(i, a, b) for i, (a, b) in span.items()
              if a.day == 1 and b.month == a.month and (b + dt.timedelta(days=1)).day == 1]
    unlinked = []
    for i, day in days:
        for kind, holders in (("month", months), ("week", weeks)):
            holder = next((h for h, a, b in holders if a <= day <= b), None)
            if holder is None:
                unlinked.append(f"{day} (no {kind} page)")
            elif i not in graph[holder]:
                unlinked.append(f"{day} (from its {kind})")
    if days and not unlinked:
        print(f"  {pdf.name}: {len(days)} days linked from {len(months)} months and {len(weeks)} weeks")
    if unlinked:
        problems.append(f"{pdf.name}: {len(unlinked)} days aren't linked, e.g. {unlinked[:5]}")
    count = len(graph)
    over = [p["pdfPage"] for p in pages if not 1 <= p["pdfPage"] <= count]
    if over or len(pages) != count:
        problems.append(f"{pdf.name}: the spec lists {len(pages)} pages; the PDF has {count}")
    return problems


def spec_for(folder, pdf, base):
    """The spec of [pdf]: its variant's own spec file, or template.json."""
    for v in base.get("variants", []):
        if v.get("file") == pdf.name and v.get("spec"):
            return json.loads((folder / v["spec"]).read_text())
    return base


def check(folder):
    problems = []
    base = json.loads((folder / "template.json").read_text())
    for pdf in sorted(folder.glob("template*.pdf")):
        spec = spec_for(folder, pdf, base)
        try:
            graph = links(pdf)
        except ValueError as e:
            problems.append(f"{pdf.name}: {e}")
            continue
        if not any(graph):
            continue
        reach = depths(graph)
        missing = [i + 1 for i in range(len(graph)) if i not in reach]
        if missing:
            problems.append(f"{pdf.name}: {len(missing)} pages can't be reached, e.g. {missing[:5]}")
        # planner_nav's books (Overview first) list groups too, but some
        # show only school days on their week pages.
        if "groups" in base and base["sections"][0]["title"] != "Overview":
            problems += check_book(pdf, spec, graph, reach)
            continue
        sections = spec.get("sections", [])
        if not sections or sections[0]["pages"][0]["title"] != "Home":
            continue
        no_home = [i + 1 for i, targets in enumerate(graph) if i and 0 not in targets]
        if no_home:
            problems.append(f"{pdf.name}: {len(no_home)} pages don't link Home, e.g. {no_home[:5]}")
        deep = [i + 1 for i, d in reach.items() if d > 3]
        if deep:
            problems.append(f"{pdf.name}: {len(deep)} pages are over 3 taps from Home, e.g. {deep[:5]}")
        by_title = {s["title"]: [p["pdfPage"] - 1 for p in s["pages"]] for s in sections}
        year = by_title["Overview"][1]
        months = by_title["Months"][::4]
        for day in by_title["Days"]:
            if day not in graph[year]:
                problems.append(f"{pdf.name}: the year page doesn't link day page {day + 1}")
                break
        month_links = set().union(*(graph[m] for m in months))
        unlinked = [d + 1 for d in by_title["Days"] if d not in month_links]
        if unlinked:
            problems.append(f"{pdf.name}: {len(unlinked)} days aren't linked from a month, e.g. {unlinked[:5]}")
    return problems


def main():
    args = sys.argv[1:]
    if args == ["--all"]:
        folders = [f for f in sorted((ROOT / "catalog").iterdir()) if (f / "template.json").exists()]
    elif args:
        folders = [Path(a) for a in args]
    else:
        sys.exit(__doc__)
    failed = False
    for folder in folders:
        problems = check(folder)
        failed |= bool(problems)
        for problem in problems:
            print(f"{folder.name}: {problem}")
    if failed:
        sys.exit(1)
    print(f"{len(folders)} templates: links OK")


if __name__ == "__main__":
    main()
