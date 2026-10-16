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


def check(folder):
    problems = []
    spec = json.loads((folder / "template.json").read_text())
    for pdf in sorted(folder.glob("template*.pdf")):
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
