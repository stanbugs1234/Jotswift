"""Builds Jotswift's bestseller-style planners: Focus (ADHD), Wellness,
Life, Goals & Projects, Student and Business, each dated and undated.

  python3 tool/make_life_planners.py focus              # one planner, both years
  python3 tool/make_life_planners.py --all
  python3 tool/make_life_planners.py --all --edition span   # just Oct 2026 - Dec 2027
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
from functools import partial
from pathlib import Path

import make_planner as mp
import planner_pages as pg
from planner_kit import Book, Collection, Group, Kind, hex_rgb, write_pdf

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog"
YEAR = 2027

# Suggested US prices (see docs/pricing.md). Etsy sells planners like
# these for $10-34 list, often $4-15 on sale; ours undercut that and stay
# well under Pro ($19.99/year), which includes them all.
PRICES = {"focus": "7.99", "wellness": "7.99", "life": "7.99", "business": "7.99",
          "goals": "6.99", "student": "6.99"}
# All twelve are also in bundle_life_planners (tool/bundles.json).

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
        tags=["adhd", "focus", "time blocking", "brain dump", "wellness", "productivity", "linked"],
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


def series(name, body, n):
    return [(f"{name} {k + 1}", body) for k in range(n)]


def reflect(prompts):
    return partial(pg.month_review, prompts=prompts)


def wellness():
    return dict(
        title="Wellness Planner", subtitle="Check in with yourself, every day.",
        style=style("#5E5A9C", "#ECEAF6", "#FCFBFE"),
        tags=["wellness", "mental health", "self-care", "journal", "therapy", "linked"],
        front=[("Year in pixels", "heart", pg.year_pixels, "start"),
               ("Intentions", "star", pg.year_goals, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Mind", pg.month_mental_health, "mind"),
                     Kind("Habits", pg.month_habits, "habits"),
                     Kind("Reflect", reflect([("Highs", "star", None), ("Lows", "cloud", None),
                                              ("What helped", "leaf", None), ("Boundaries", "check", None),
                                              ("Joy", "sun", None), ("Next month I need", "heart", None)]),
                          "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Check-in", pg.week_review, "week_review")],
        day_kinds=[Kind("Journal", pg.day_journal, "days")],
        collections=[Collection("therapy", "Therapy notes", "cloud", "therapy", series("Session", pg.therapy_notes, 24),
                                "Before, during and after each session."),
                     Collection("anxiety", "Anxiety journal", "leaf", "anxiety",
                                series("Entry", pg.anxiety_journal, 12), "Untangle a worry, one question at a time."),
                     Collection("toolkit", "Toolkit", "heart", "toolkit",
                                [("Self-care menu", pg.self_care_menu), ("Sleep log", pg.sleep_log),
                                 ("Sleep log 2", pg.sleep_log), ("Stress tracker", pg.stress_tracker),
                                 ("Stress tracker 2", pg.stress_tracker)], "What helps, when you need it."),
                     Collection("gratitude", "Gratitude", "star", "gratitude", series("Gratitude", pg.gratitude, 12),
                                "Three good things."),
                     notes()],
        groups=[Group("weeks", "Week pages"), Group("week_review", "Weekly check-ins"),
                Group("days", "Daily journal pages"), Group("mind", "Monthly mental health"),
                Group("habits", "Habit trackers"), Group("month_review", "Monthly reflections"),
                Group("therapy", "Therapy notes"), Group("anxiety", "Anxiety journal"),
                Group("toolkit", "Toolkit"), Group("gratitude", "Gratitude journal"), Group("notes", "Notes")],
    )


def life():
    return dict(
        title="Life Planner", subtitle="Plan the days, grow the life.",
        style=style("#A9553A", "#F5E8E1", "#FFFCF8"),
        tags=["life", "goals", "budget", "habits", "vision board", "meal planning", "linked"],
        front=[("Year goals", "target", pg.year_goals, "start"),
               ("Vision board", "star", pg.vision_board, "start"),
               ("Year in pixels", "heart", pg.year_pixels, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Goals", pg.month_goals, "month_goals"),
                     Kind("Vision", pg.vision_board, "vision"),
                     Kind("Habits", pg.month_habits, "habits"),
                     Kind("Budget", pg.month_budget, "budget"),
                     Kind("Wins", pg.wins, "wins"),
                     Kind("Reflect", pg.month_review, "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Meals", pg.meals_movement, "meals"),
                    Kind("Review", pg.week_review, "week_review")],
        day_kinds=[Kind("Day", pg.day_life, "days")],
        collections=[Collection("finance", "Finance", "coin", "finance",
                                [("Year overview", pg.finance_overview), ("Bills", pg.bills_tracker),
                                 ("Savings goals", pg.savings_goals), ("Debt payoff", pg.debt_payoff),
                                 ("Subscriptions", pg.subscriptions), ("Wishlist", pg.wishlist)],
                                "Your money, month by month."),
                     Collection("health", "Health", "leaf", "health",
                                [("Meal plan", pg.meal_plan), ("Sleep log", pg.sleep_log),
                                 ("Reading log", pg.reading_log)], "Eat, move, rest."),
                     Collection("home", "Home", "home", "home_pages",
                                [("Cleaning schedule", pg.cleaning_schedule), ("Groceries", pg.checklist_page),
                                 ("Projects", pg.checklist_page), ("Gift ideas", pg.checklist_page)],
                                "Keep the house running."),
                     Collection("travel", "Travel", "plane", "travel", series("Trip", pg.trip_planner, 4),
                                "Plan every getaway."),
                     notes()],
        groups=[Group("weeks", "Week pages"), Group("meals", "Weekly meals & movement"),
                Group("week_review", "Weekly reviews"), Group("days", "Daily pages"),
                Group("month_goals", "Monthly goals"), Group("vision", "Monthly vision boards"),
                Group("habits", "Habit trackers"), Group("budget", "Monthly budgets"),
                Group("wins", "Monthly wins"), Group("month_review", "Monthly reflections"),
                Group("finance", "Finance"), Group("health", "Health"), Group("home_pages", "Home"),
                Group("travel", "Travel"), Group("notes", "Notes")],
    )


def goals():
    return dict(
        title="Goals & Projects", subtitle="From a dream to this week's next step.",
        style=style("#1F3D63", "#E6ECF4"),
        category="productivity",
        tags=["goals", "projects", "productivity", "dashboard", "quarterly", "linked"],
        front=[("Goal roadmap", "target", pg.goal_roadmap, "start"),
               ("Year goals", "star", pg.year_goals, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Milestones", pg.milestones, "milestones"),
                     Kind("Review", pg.month_review, "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Review", pg.week_review, "week_review")],
        day_kinds=[Kind("Day", pg.day_goals, "days")],
        collections=[Collection("goals", "Goals", "target", "goal_pages", series("Goal", pg.goal_dashboard, 12),
                                "One dashboard per goal: why, milestones, steps."),
                     Collection("projects", "Projects", "briefcase", "projects",
                                series("Project", pg.project_dashboard, 12), "Outcome, tasks and notes."),
                     Collection("quarters", "Quarters", "chart", "quarters",
                                [(f"Q{k + 1} review", pg.quarter_review) for k in range(4)],
                                "Step back every three months."),
                     notes()],
        groups=[Group("weeks", "Week pages"), Group("week_review", "Weekly reviews"),
                Group("days", "Daily pages"), Group("milestones", "Monthly milestones"),
                Group("month_review", "Monthly reviews"), Group("goal_pages", "Goal dashboards"),
                Group("projects", "Project dashboards"), Group("quarters", "Quarterly reviews"),
                Group("notes", "Notes")],
    )


def student():
    return dict(
        title="Student Planner", subtitle="Classes, deadlines and study time, August to July.",
        style=style("#2C5BA6", "#E5EDF9"),
        academic=True,
        tags=["student", "academic", "school", "college", "study", "assignments", "linked"],
        front=[("Class schedule", "cap", pg.class_schedule, "start"),
               ("Year goals", "target", pg.year_goals, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Assignments", pg.assignment_tracker, "assignments"),
                     Kind("Review", pg.month_review, "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Review", pg.week_review, "week_review")],
        day_kinds=[Kind("Day", pg.day_student, "days")],
        collections=[Collection("courses", "Courses", "book", "courses", series("Course", pg.course_dashboard, 8),
                                "One page per class: assignments, grades, notes."),
                     Collection("exams", "Exams", "cap", "exams", series("Exam plan", pg.exam_planner, 3),
                                "Plan your revision."),
                     Collection("study", "Study", "target", "study",
                                [("Pomodoro log", pg.pomodoro), ("Pomodoro log 2", pg.pomodoro),
                                 ("GPA tracker", pg.gpa_tracker), ("Reading log", pg.reading_log)],
                                "Focus sessions, grades and reading."),
                     notes(30)],
        groups=[Group("weeks", "Week pages"), Group("week_review", "Weekly reviews"),
                Group("days", "Daily pages"), Group("assignments", "Monthly assignment trackers"),
                Group("month_review", "Monthly reviews"), Group("courses", "Course pages"),
                Group("exams", "Exam plans"), Group("study", "Study logs"), Group("notes", "Class notes")],
    )


def business():
    return dict(
        title="Business Planner", subtitle="Strategy, clients and money, in one place.",
        style=style("#2F343B", "#ECEAE4", "#FFFEFB"),
        tags=["business", "work", "clients", "marketing", "finance", "content", "productivity", "linked"],
        front=[("Year review", "star", pg.year_review, "start"),
               ("Strategy", "target", pg.business_strategy, "start"),
               ("Marketing plan", "chart", pg.marketing_plan, "start"),
               ("Year goals", "check", pg.year_goals, "start")],
        month_kinds=[Kind("Calendar", pg.month_calendar, "months"),
                     Kind("Content", pg.content_calendar, "content"),
                     Kind("Money", pg.income_expenses, "money"),
                     Kind("Review", pg.month_review, "month_review")],
        week_kinds=[Kind("Week", pg.week_plan, "weeks"),
                    Kind("Review", pg.week_review, "week_review")],
        day_kinds=[Kind("Day", pg.day_business, "days")],
        collections=[Collection("clients", "Clients", "people", "clients", series("Client", pg.client_card, 20),
                                "Contacts, projects and invoices."),
                     Collection("projects", "Projects", "briefcase", "projects",
                                series("Project", pg.project_dashboard, 12), "Outcome, tasks and notes."),
                     Collection("finance", "Finance", "coin", "finance",
                                [("Year overview", pg.finance_overview), ("Subscriptions", pg.subscriptions),
                                 ("Savings goals", pg.savings_goals)], "The year's numbers."),
                     notes()],
        groups=[Group("weeks", "Week pages"), Group("week_review", "Weekly reviews"),
                Group("days", "Daily pages"), Group("content", "Content calendars"),
                Group("money", "Monthly income & expenses"), Group("month_review", "Monthly reviews"),
                Group("clients", "Client pages"), Group("projects", "Project dashboards"),
                Group("finance", "Finance"), Group("notes", "Notes")],
    )


PLANNERS = {"focus": focus, "wellness": wellness, "life": life, "goals": goals, "student": student,
            "business": business}


# Building

# Editions: "year" (2027, or 2026-27 from August for academic planners),
# "span" (October 2026 to December 2027, to start the planner now) and
# "undated".
SPAN_START, SPAN_MONTHS = dt.date(YEAR - 1, 10, 1), 15


def editions(key):
    if PLANNERS[key]().get("academic"):
        return ["year", "undated"]
    return ["year", "span", "undated"]


def make_book(make, edition, week_start):
    cfg = make()
    mp.use_style(cfg["style"])
    start, months = None, 12
    if edition == "year":
        start = dt.date(YEAR - 1, 8, 1) if cfg.get("academic") else dt.date(YEAR, 1, 1)
    elif edition == "span":
        start, months = SPAN_START, SPAN_MONTHS
    return Book(cfg["title"], cfg["subtitle"], start, week_start=week_start, front=cfg["front"],
                month_kinds=cfg["month_kinds"], week_kinds=cfg["week_kinds"], day_kinds=cfg["day_kinds"],
                collections=cfg["collections"], groups=cfg["groups"], months=months), cfg


def file_name(layout, week, ext):
    parts = [x for x in (layout if layout != "landscape" else "", week if week != "monday" else "") if x]
    return "template" + "".join(f"_{x}" for x in parts) + ext


def item_id(key, edition):
    if edition == "undated":
        return f"{key}_planner_undated"
    if edition == "span" or PLANNERS[key]().get("academic"):
        return f"{key}_planner_{YEAR - 1}_{str(YEAR)[2:]}"
    return f"{key}_planner_{YEAR}"


def write(key, edition):
    folder = CATALOG / item_id(key, edition)
    folder.mkdir(parents=True, exist_ok=True)
    variants, base = [], None
    for layout, layout_name, size in LAYOUTS:
        mp.use_size(*size)
        for week, week_name, week_start in WEEK_STARTS:
            book, cfg = make_book(PLANNERS[key], edition, week_start)
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
    write_listing(folder, cfg, edition, key)


def product_id(key, edition):
    """planner_focus_2027, planner_focus_2026 (October 2026 to December
    2027; for the Student planner, 2026-27), or pack_focus_undated."""
    if edition == "undated":
        return f"pack_{key}_undated"
    if edition == "span" or PLANNERS[key]().get("academic"):
        return f"planner_{key}_{YEAR - 1}"
    return f"planner_{key}_{YEAR}"


def listing_name(cfg, edition):
    if edition == "undated":
        return f"{cfg['title']} (undated)"
    if edition == "span":
        return f"{cfg['title']} Oct {YEAR - 1} - Dec {YEAR}"
    return f"{cfg['title']} {book_year(cfg)}"


def write_listing(folder, cfg, edition, key):
    path = folder / "listing.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    years = {"year": ["dated", book_year(cfg)], "span": ["dated", str(YEAR - 1), str(YEAR), "15 months"],
             "undated": ["undated"]}[edition]
    listing = {
        "kind": "template",
        "name": listing_name(cfg, edition),
        "version": old.get("version", 1),
        "unlock": {"pro": True, "products": [product_id(key, edition)]},
        "category": cfg.get("category", "planners"),
        "tags": [*cfg["tags"], *years, "landscape", "portrait"],
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
        book, _ = make_book(PLANNERS[key], "span" if "--span" in sys.argv else "year", 0)
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


def listings_only():
    """Rewrites every listing.json without rebuilding the PDFs."""
    for key in PLANNERS:
        for edition in editions(key):
            cfg = PLANNERS[key]()
            write_listing(CATALOG / item_id(key, edition), cfg, edition, key)


def main():
    args = sys.argv[1:]
    if args == ["--listings"]:
        listings_only()
        return
    if "--sample" in args:
        i = args.index("--sample")
        sample(args[0], args[i + 1])
        return
    only = None
    if "--edition" in args:
        i = args.index("--edition")
        only = args[i + 1]
        del args[i:i + 2]
    keys = list(PLANNERS) if args == ["--all"] else args
    if not keys:
        sys.exit(__doc__)
    for key in keys:
        for edition in editions(key):
            if only in (None, edition):
                write(key, edition)


if __name__ == "__main__":
    main()
