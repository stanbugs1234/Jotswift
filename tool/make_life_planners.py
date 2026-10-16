"""Builds Jotswift's bestseller-style planners: Focus (ADHD), Wellness,
Life, Goals & Projects, Student and Business, each dated and undated.

  python3 tool/make_life_planners.py focus              # one planner, both years
  python3 tool/make_life_planners.py --all
  python3 tool/make_life_planners.py focus --sample OUT  # PNGs of sample pages

Each listing holds four PDFs, one per layout (landscape, portrait) and week
start (Monday, Sunday), and a template json for each; the app's planner
builder picks one, and leaves out the optional groups the user turns off.
See planner_kit.py for the book and planner_pages.py for the pages.
"""

import datetime as dt
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import make_planner as mp
import planner_pages as pg
from planner_kit import Book, Collection, Group, Kind, hex_rgb, write_pdf

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog"
YEAR = 2027

LAYOUTS = [("landscape", "Landscape", (792, 612)), ("portrait", "Portrait", (612, 792))]
WEEK_STARTS = [("monday", "Monday", 0), ("sunday", "Sunday", 6)]


def style(accent, tab, paper="#FFFFFF", ink="#1F2430", soft="#8A919C", rule="#D5D9DF"):
    return mp.Style(ink=hex_rgb(ink), soft=hex_rgb(soft), rule=hex_rgb(rule), accent=hex_rgb(accent),
                    tab=hex_rgb(tab), paper=None if paper == "#FFFFFF" else hex_rgb(paper))


def notes(n=20):
    return Collection("notes", "Notes", "pencil", "notes",
                      [(f"Note {k + 1}", pg.lined_page) for k in range(n)], "Lined pages for anything.")


# The planners. Each returns Book keyword arguments.

def focus():
    return dict(
        title="Focus Planner", subtitle="An ADHD-friendly planner: one thing at a time.",
        style=style("#2F6F6A", "#E6F0EE", "#FBFBF8"),
        tags=["adhd", "focus", "time blocking", "brain dump", "wellness", "linked"],
        front=[("Year goals", "target", pg.year_goals, "start"),
               ("Year in pixels", "heart", pg.year_pixels, "start"),
               ("Routines", "sun", pg.routines, "start"),
               ("Rewards menu", "gift", pg.rewards_menu, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Habits", pg.month_habits, "habits"),
                     Kind("Review", pg.month_review, "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Review", pg.week_review, "week_review")],
        day_kinds=[Kind("Plan", pg.day_focus, "days"),
                   Kind("Check-in", pg.day_checkin, "checkin")],
        collections=[Collection("dumps", "Brain dumps", "cloud", "dumps",
                                [(f"Brain dump {k + 1}", pg.brain_dump) for k in range(12)],
                                "Empty your head, then sort it out."),
                     Collection("breakdowns", "Task breakdowns", "list", "breakdowns",
                                [(f"Task {k + 1}", pg.task_breakdown) for k in range(12)],
                                "Big, scary tasks broken into tiny steps."),
                     notes()],
        groups=[Group("weeks", "Week pages"), Group("week_review", "Weekly reviews"),
                Group("days", "Daily plans"), Group("checkin", "Daily check-ins"),
                Group("habits", "Habit trackers"), Group("month_review", "Monthly reviews"),
                Group("dumps", "Brain dumps"), Group("breakdowns", "Task breakdowns"),
                Group("notes", "Notes")],
    )


PLANNERS = {"focus": focus}


# Building

def make_book(make, dated, week_start):
    cfg = make()
    mp.use_style(cfg["style"])
    start = dt.date(YEAR, 1, 1) if dated else None
    if dated and cfg.get("academic"):
        start = dt.date(YEAR - 1, 8, 1)
    return Book(cfg["title"], cfg["subtitle"], start, week_start=week_start, front=cfg["front"],
                month_kinds=cfg["month_kinds"], week_kinds=cfg["week_kinds"], day_kinds=cfg["day_kinds"],
                collections=cfg["collections"], groups=cfg["groups"]), cfg


def file_name(layout, week, ext):
    parts = [x for x in (layout if layout != "landscape" else "", week if week != "monday" else "") if x]
    return "template" + "".join(f"_{x}" for x in parts) + ext


def item_id(key, dated):
    return f"{key}_planner_{YEAR}" if dated else f"{key}_planner_undated"


def write(key, dated):
    folder = CATALOG / item_id(key, dated)
    folder.mkdir(parents=True, exist_ok=True)
    variants, base = [], None
    for layout, layout_name, size in LAYOUTS:
        mp.use_size(*size)
        for week, week_name, week_start in WEEK_STARTS:
            book, cfg = make_book(PLANNERS[key], dated, week_start)
            pages, spec = book.build()
            pdf, js = file_name(layout, week, ".pdf"), file_name(layout, week, ".json")
            write_pdf(pages, folder / pdf)
            variant = {"name": f"{layout_name} · {week_name}", "file": pdf,
                       "options": {"layout": layout, "weekStart": week}}
            if base is None:
                base = (spec, book, cfg)
            else:
                (folder / js).write_text(json.dumps({"sections": spec["sections"]}, indent=1))
                variant["spec"] = js
            variants.append(variant)
            print(f"  {folder.name}/{pdf}: {len(pages)} pages, {(folder / pdf).stat().st_size // 1024} KB")
    spec, book, cfg = base
    spec["options"] = [
        {"id": "layout", "title": "Layout", "choices": [{"id": i, "name": n} for i, n, _ in LAYOUTS]},
        {"id": "weekStart", "title": "Week starts", "choices": [{"id": i, "name": n} for i, n, _ in WEEK_STARTS]},
    ]
    spec["groups"] = [{"id": g.id, "title": g.title, "optional": g.optional, "on": g.on} for g in book.groups]
    spec["variants"] = variants
    (folder / "template.json").write_text(json.dumps(spec, indent=1))
    mp.use_size(*LAYOUTS[0][2])
    mp.use_style(cfg["style"])
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")
    write_listing(folder, cfg, dated)


def write_listing(folder, cfg, dated):
    path = folder / "listing.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    name = f"{cfg['title']} {book_year(cfg)}" if dated else f"{cfg['title']} (undated)"
    listing = {
        "kind": "template",
        "name": name,
        "version": old.get("version", 1),
        "unlock": old.get("unlock", {"pro": True, "products": [f"planner_{folder.name}"]}),
        "category": "planners",
        "tags": [*cfg["tags"], *(["dated", book_year(cfg)] if dated else ["undated"]),
                 "landscape", "portrait"],
    }
    path.write_text(json.dumps(listing, indent=2) + "\n")


def book_year(cfg):
    return f"{YEAR - 1}-{str(YEAR)[2:]}" if cfg.get("academic") else str(YEAR)


def sample(key, out):
    """Writes PNGs of a page of each kind, both layouts, to [out]."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for layout, _, size in LAYOUTS:
        mp.use_size(*size)
        book, _ = make_book(PLANNERS[key], True, 0)
        picks = {"home": book.home, "year": book.year_page}
        for k, page in enumerate(book.front_pages):
            picks[f"front{k}"] = page
        for s, page in enumerate(book.month_page[2]):
            picks[f"month{s}"] = page
        w = book.week_of(book.days_of_month(2)[10])
        for s, page in enumerate(book.week_page[w]):
            picks[f"week{s}"] = page
        for s, page in enumerate(book.day_page[book.days_of_month(2)[10]]):
            picks[f"day{s}"] = page
        for c in book.collections:
            picks[f"{c.key}_index"] = c.index
            picks[f"{c.key}_page"] = c.page_ids[0]
        for name, i in picks.items():
            p = mp.Page()
            book.recs[i].draw(p)
            p.links = []
            with tempfile.TemporaryDirectory() as tmp:
                pdf = Path(tmp) / "p.pdf"
                write_pdf([p], pdf)
                subprocess.run(["sips", "-s", "format", "png", "-Z", "1400", str(pdf), "--out",
                                str(out / f"{key}_{layout}_{name}.png")], check=True, capture_output=True)
    print(f"samples in {out}")


def main():
    args = sys.argv[1:]
    if "--sample" in args:
        i = args.index("--sample")
        sample(args[0], args[i + 1])
        return
    keys = list(PLANNERS) if args == ["--all"] else args
    if not keys:
        sys.exit(__doc__)
    for key in keys:
        for dated in (True, False):
            write(key, dated)


if __name__ == "__main__":
    main()
