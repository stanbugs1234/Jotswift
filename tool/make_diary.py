"""Makes Jotswift's linked diaries and planners. Each is laid out by
planner_nav (Home, year, months with goals and habits, weeks, days, notes
and lists, all linked); this file gives each book its look and pages.

  python3 tool/make_diary.py diary_classic 2027      # catalog/diary_classic_2027/
  python3 tool/make_diary.py all 2027                # every book below
  python3 tool/make_diary.py --list

Books (see BOOKS): Classic, Modern and Landscape daily/weekly diaries,
three tabbed diaries in different colours, Academic and Teacher planners
(July to June) and undated weekly and daily planners. Dated books need a
year; academic ones start in July of that year.

Writes template.pdf, template.json, preview.webp and listing.json.
Re-running keeps each item's version; raise it by hand when pages change.
Needs Pillow, and macOS `sips` for the preview.
"""

import calendar
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_planner as mp  # noqa: E402
import planner_nav as nav  # noqa: E402
from make_planner import Style, header, tint  # noqa: E402
from planner_nav import day_plan, rgb, week_boxes  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MONTHS = list(calendar.month_name)[1:]
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def S():
    return mp.S


# Styles. Tab colours, when set, give each month its own tab colour.

CLASSIC = Style(ink=rgb("#2B2622"), soft=rgb("#8C8176"), rule=rgb("#DCD3C4"), accent=rgb("#6B3E2E"),
                tab=rgb("#F1EADF"), paper=rgb("#FBF8F2"), border="double", header="underline", serif=True)
MODERN = Style(ink=rgb("#1E2328"), soft=rgb("#7C8790"), rule=rgb("#DDE3E8"), accent=rgb("#1F6F78"),
               tab=rgb("#E7F1F2"), header="banner")
LANDSCAPE = Style(ink=rgb("#23262B"), soft=rgb("#858B94"), rule=rgb("#DADFE6"), accent=rgb("#3A4E7A"),
                  tab=rgb("#ECEFF5"))
LAVENDER = Style(ink=rgb("#2E2A3A"), soft=rgb("#8D86A3"), rule=rgb("#E2DCF0"), accent=rgb("#6A5A9C"),
                 tab=rgb("#F0ECF8"), paper=rgb("#FDFCFF"), header="swash", motif="stars")
LINEN = Style(ink=rgb("#33291F"), soft=rgb("#957F68"), rule=rgb("#E6D9C6"), accent=rgb("#8A5A33"),
              tab=rgb("#F3EBDD"), paper=rgb("#FBF6EE"), border="stitched", header="underline", serif=True)
SORBET = Style(ink=rgb("#3A2B2E"), soft=rgb("#A08588"), rule=rgb("#F2DCDD"), accent=rgb("#C2566A"),
               tab=rgb("#FBEDEE"), paper=rgb("#FFFCFB"), header="banner", motif="hearts")
ACADEMIC = Style(ink=rgb("#1F2433"), soft=rgb("#7F879B"), rule=rgb("#D9DEEA"), accent=rgb("#2F4B8C"),
                 tab=rgb("#E9EEF8"), header="underline")
TEACHER = Style(ink=rgb("#26302A"), soft=rgb("#7E8C82"), rule=rgb("#D7E2DA"), accent=rgb("#3D7A55"),
                tab=rgb("#E8F2EB"), header="banner")
UNDATED = Style(ink=rgb("#24272B"), soft=rgb("#848A91"), rule=rgb("#DDE0E4"), accent=rgb("#4E5A66"),
                tab=rgb("#EEF0F2"))

RAINBOW = {
    "lavender": ["#B9A7E0", "#A7B7E8", "#9CCBE0", "#A2D6C4", "#BFDBA2", "#E2D99A",
                 "#EFC79C", "#EEB0A6", "#E7A6C1", "#D2A6DC", "#B9A7E0", "#A7B7E8"],
    "linen": ["#C9A27E", "#B88E6A", "#A98263", "#9C8F6B", "#8F9873", "#86977F",
              "#8A8E8B", "#998478", "#AA7F6E", "#B98A72", "#C6987A", "#D2A784"],
    "sorbet": ["#F4A6A6", "#F6BE9A", "#F5D58E", "#C9E3A0", "#A6DCC6", "#9FD0E8",
               "#AFB8EC", "#C8AEEA", "#E6A8DA", "#F2A6BE", "#F4A6A6", "#F6BE9A"],
}


# Page bodies: what goes under a day's or week's title.

def _lines(p, x0, x1, top, bottom, gap=24):
    y = top
    while y >= bottom:
        p.line(x0, y, x1, y)
        y -= gap


def _label(p, x, y, text, size=10):
    p.text(x, y, text, size, rgb=S().accent, bold=True)


def _checks(p, x0, x1, top, count, gap=24):
    for k in range(count):
        y = top - k * gap
        p.rect(x0, y - 2, 10, 10, stroke=S().soft, width=1)
        p.line(x0 + 18, y - 3, x1, y - 3)


def classic_day(book, p, i, left, right, top):
    """A diary page: a short 'today' box, then lines."""
    p.rect(left, top - 58, right - left, 50, fill=tint(S().accent, 0.92))
    p.text(left + 10, top - 26, "Weather", 9, rgb=S().soft, bold=True)
    p.text(left + 150, top - 26, "Mood", 9, rgb=S().soft, bold=True)
    p.text(left + 280, top - 26, "Grateful for", 9, rgb=S().soft, bold=True)
    for x in (left + 10, left + 150, left + 280):
        p.line(x, top - 46, x + (120 if x < left + 280 else right - left - 300), top - 46)
    _lines(p, left, right, top - 86, 44, 24)


def tabbed_day(book, p, i, left, right, top):
    """Lined with a small habit row and water glasses."""
    _label(p, left, top - 14, "Today")
    _checks(p, left, right, top - 38, 4)
    _label(p, left, top - 152, "Notes")
    _lines(p, left, right, top - 176, 104, 24)
    p.text(left, 76, "Water", 9, rgb=S().soft, bold=True)
    for k in range(8):
        p.rect(left + 44 + k * 18, 70, 12, 14, stroke=S().rule)
    p.text(left + 210, 76, "Sleep  ____ h", 9, rgb=S().soft, bold=True)
    p.text(left + 310, 76, "Move  ____ min", 9, rgb=S().soft, bold=True)
    p.text(left, 52, "Highlight", 9, rgb=S().soft, bold=True)
    p.line(left + 52, 49, right, 49)


def week_columns(book, p, i, left, right, top):
    """Landscape: seven day columns and a notes strip."""
    cw = (right - left) / 7
    days = book.week_days(i)
    for d in range(7):
        x = left + d * cw
        p.rect(x, 96, cw, top - 96, stroke=S().rule)
        p.rect(x, top - 26, cw, 26, fill=S().tab)
        name = DAYS[d][:3]
        if days:
            name += f"  {days[d].day}"
            book.link_day(p, x, top - 26, cw, 26, days[d])
        p.text(x + 8, top - 17, name, 10, rgb=S().accent, bold=True)
        _lines(p, x + 6, x + cw - 6, top - 50, 104, 22)
    _label(p, left, 80, "This week")
    _checks(p, left + 70, left + (right - left) / 2, 82, 2)
    _label(p, left + (right - left) / 2 + 12, 80, "Notes")
    _lines(p, left + (right - left) / 2 + 60, right, 76, 40, 22)


def academic_week(book, p, i, left, right, top):
    """Days down the side with room for classes, homework and due dates."""
    monday = book.weeks[i]
    w = right - left
    cols = [("", 0), ("Classes & notes", 0.18), ("Homework", 0.56), ("Due", 0.86)]
    p.rect(left, top - 22, w, 22, fill=S().tab)
    for name, at in cols:
        _label(p, left + w * at + 6, top - 15, name, 9)
    rh = (top - 22 - 120) / 7
    for d in range(7):
        y = top - 22 - (d + 1) * rh
        day = monday + dt.timedelta(days=d)
        _label(p, left + 6, y + rh - 16, DAYS[d][:3], 10)
        p.text(left + 6, y + rh - 30, f"{MONTHS[day.month - 1][:3]} {day.day}", 8, rgb=S().soft)
        book.link_day(p, left, y, w * 0.18, rh, day)
        p.line(left, y, right, y)
        for _, at in cols[1:]:
            p.line(left + w * at, y, left + w * at, y + rh, rgb=tint(S().rule, 0.3), width=0.6)
        _lines(p, left + w * 0.18 + 6, right - 6, y + rh - 18, y + 6, 18)
    _label(p, left, 104, "This week's focus")
    _lines(p, left, right, 84, 44, 22)


def lesson_week(book, p, i, left, right, top):
    """Teacher: periods across, days down."""
    monday = book.weeks[i]
    periods = 6
    name_w = 64
    cw = (right - left - name_w) / periods
    for k in range(periods):
        p.rect(left + name_w + k * cw, top - 24, cw, 24, fill=S().tab)
        _label(p, left + name_w + k * cw + 8, top - 16, f"Period {k + 1}", 9)
    rh = (top - 24 - 40) / 5
    for d in range(5):
        y = top - 24 - (d + 1) * rh
        day = monday + dt.timedelta(days=d)
        _label(p, left, y + rh - 16, DAYS[d][:3], 10)
        p.text(left, y + rh - 30, f"{MONTHS[day.month - 1][:3]} {day.day}", 8, rgb=S().soft)
        book.link_day(p, left, y, name_w, rh, day)
        for k in range(periods):
            p.rect(left + name_w + k * cw, y, cw, rh, stroke=S().rule)
            _lines(p, left + name_w + k * cw + 6, left + name_w + (k + 1) * cw - 6, y + rh - 20, y + 8, 18)


# Front pages for the academic and teacher planners.

def _front_table(title, cols, rows, row_h=26):
    def draw(book, p):
        left, right = 40, book.right
        header(p, left, mp.H - 66, title, 26)
        top = mp.H - 96
        w = right - left
        p.rect(left, top - 22, w, 22, fill=S().tab)
        for name, at in cols:
            _label(p, left + w * at + 6, top - 15, name, 9)
        for r in range(rows):
            y = top - 22 - (r + 1) * row_h
            p.line(left, y, right, y)
        for _, at in cols[1:]:
            p.line(left + w * at, top - 22, left + w * at, top - 22 - rows * row_h, rgb=tint(S().rule, 0.3), width=0.6)
    return draw


def _class_schedule(book, p):
    left, right = 40, book.right
    header(p, left, mp.H - 66, "Class schedule", 26)
    top = mp.H - 96
    tw = 44
    cw = (right - left - tw) / 5
    for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri"]):
        p.rect(left + tw + i * cw, top - 24, cw, 24, fill=S().tab)
        _label(p, left + tw + i * cw + 8, top - 16, d)
    rh = (top - 24 - 50) / 10
    for r in range(10):
        y = top - 24 - (r + 1) * rh
        p.text(left, y + rh - 14, f"{r + 1}", 9, rgb=S().soft, bold=True)
        for i in range(5):
            p.rect(left + tw + i * cw, y, cw, rh, stroke=S().rule, width=0.6)


def _seating(book, p):
    left, right = 40, book.right
    header(p, left, mp.H - 66, "Seating chart", 26)
    p.text(left, mp.H - 88, "Class  ________________", 11, rgb=S().soft)
    p.rect(left + (right - left) / 2 - 80, mp.H - 130, 160, 26, fill=S().tab)
    p.text((left + right) / 2, mp.H - 121, "Front", 10, rgb=S().accent, bold=True, center=True)
    cols, rows = 5, 6
    gw, gh = (right - left) / cols, (mp.H - 160 - 50) / rows
    for r in range(rows):
        for c in range(cols):
            x, y = left + c * gw + 8, mp.H - 160 - (r + 1) * gh + 8
            p.rect(x, y, gw - 16, gh - 16, stroke=S().rule)


ACADEMIC_FRONT = [
    ("Class schedule", _class_schedule),
    ("Assignments", _front_table("Assignments", [("Done", 0), ("Class", 0.08), ("Assignment", 0.3), ("Due", 0.78), ("Grade", 0.9)], 22)),
    ("Exams", _front_table("Exams", [("Subject", 0), ("Date", 0.32), ("Time", 0.48), ("Room", 0.62), ("Topics", 0.76)], 22)),
    ("Grades", _front_table("Grades", [("Course", 0), ("Term 1", 0.4), ("Term 2", 0.55), ("Term 3", 0.7), ("Final", 0.85)], 22)),
]
TEACHER_FRONT = [
    ("Class list", _front_table("Class list", [("#", 0), ("Student", 0.06), ("Contact", 0.45), ("Notes", 0.72)], 24, row_h=24)),
    ("Gradebook", _front_table("Gradebook", [("Student", 0)] + [(f"{k + 1}", 0.3 + k * 0.07) for k in range(10)], 24, row_h=24)),
    ("Seating chart", _seating),
    ("Timetable", _class_schedule),
]


# The books. "dated": needs a year; "start": the first month. Every book
# has month, week and day pages (see planner_nav); "day" and "week" draw
# what goes under a day's or week's title.

BOOKS = {
    "diary_classic": dict(name="Classic Daily Diary", style=CLASSIC, day=classic_day, week=week_boxes, start=1,
                          price="3.99", tags=["diary", "daily", "dated", "linked"]),
    "diary_modern": dict(name="Modern Daily Planner", style=MODERN, day=day_plan, week=week_boxes, start=1,
                         price="3.99", tags=["planner", "daily", "time blocks", "dated", "linked"]),
    "diary_landscape": dict(name="Landscape Weekly Planner", style=LANDSCAPE, day=day_plan, week=week_columns, start=1,
                            landscape=True, price="3.99", tags=["planner", "weekly", "landscape", "dated", "linked"]),
    "tabbed_lavender": dict(name="Tabbed Diary: Lavender", style=LAVENDER, day=tabbed_day, week=week_boxes, start=1,
                            tabs="lavender", price="3.99", tags=["diary", "tabbed", "pastel", "dated"]),
    "tabbed_linen": dict(name="Tabbed Diary: Linen", style=LINEN, day=tabbed_day, week=week_boxes, start=1,
                         tabs="linen", price="3.99", tags=["diary", "tabbed", "neutral", "dated"]),
    "tabbed_sorbet": dict(name="Tabbed Diary: Sorbet", style=SORBET, day=tabbed_day, week=week_boxes, start=1,
                          tabs="sorbet", price="3.99", tags=["diary", "tabbed", "colourful", "dated"]),
    "academic_planner": dict(name="Academic Planner", style=ACADEMIC, day=day_plan, week=academic_week, start=7,
                             front=ACADEMIC_FRONT, price="3.99", category="study",
                             tags=["student", "school year", "weekly", "dated"]),
    "teacher_planner": dict(name="Teacher Planner", style=TEACHER, day=day_plan, week=lesson_week, start=7,
                            front=TEACHER_FRONT, price="3.99", category="study",
                            tags=["teacher", "lesson plans", "school year", "dated"]),
    "undated_weekly": dict(name="Undated Weekly Planner", style=UNDATED, day=day_plan, week=week_boxes, dated=False,
                           price="2.99", tags=["planner", "weekly", "undated", "linked"]),
    "undated_daily": dict(name="Undated Daily Planner", style=UNDATED, day=day_plan, week=week_boxes, dated=False,
                          price="2.99", tags=["planner", "daily", "undated", "linked"]),
}


def item_id(key, year):
    book = BOOKS[key]
    if not book.get("dated", True):
        return key
    return f"{key}_{year}" if book.get("start", 1) == 1 else f"{key}_{year}_{(year + 1) % 100:02d}"


def write(key, year):
    book = BOOKS[key]
    dated = book.get("dated", True)
    mp.use_size(*((792, 612) if book.get("landscape") else (612, 792)))
    mp.use_style(book["style"])
    start = dt.date(year, book.get("start", 1), 1)
    title = book["name"].split(":")[0] if not dated else (
        str(year) if book.get("start", 1) == 1 else f"{year}-{(year + 1) % 100:02d}")
    b = nav.Planner(title, start, dated, week_body=book["week"], day_body=book["day"],
                    front=book.get("front", []), tab_colors=RAINBOW.get(book.get("tabs")),
                    subtitle=book["name"] if dated else "Fill in your own dates")
    pages, spec = b.build()
    iid = item_id(key, year)
    folder = ROOT / "catalog" / iid
    folder.mkdir(parents=True, exist_ok=True)
    mp.write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec, indent=2) + "\n")
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")
    name = book["name"]
    if dated:
        name += f" {title}"
    product = f"planner_{key}_{year}" if dated else f"pack_{key}"
    listing = {
        "kind": "template",
        "name": name,
        "version": 1,
        "unlock": {"pro": True, "products": [product]},
        "category": book.get("category", "diaries"),
        "tags": book["tags"] + ([str(year)] if dated else []),
    }
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")
    mp.use_size(612, 792)
    return iid, len(pages)


def main():
    args = sys.argv[1:]
    if args == ["--list"]:
        for key, book in BOOKS.items():
            print(f"{key:20} ${book['price']:5} {book['name']}")
        return
    if len(args) != 2 or (args[0] != "all" and args[0] not in BOOKS):
        sys.exit(__doc__)
    year = int(args[1])
    for key in BOOKS if args[0] == "all" else [args[0]]:
        iid, count = write(key, year)
        print(f"{iid}: {count} pages")


if __name__ == "__main__":
    main()
