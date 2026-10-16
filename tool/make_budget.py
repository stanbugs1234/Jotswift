"""Makes the Budget collection: an undated monthly budget planner, with
covers and stickers, all drawn in code.

  python3 tool/make_budget.py

It writes these catalog folders:

  budget/            the collection (listing + preview), sold as pack_budget
  budget_planner/    the planner: a year overview, a budget page for each
                     month, and bill, savings and debt trackers, linked by
                     tabs along the top (landscape, US Letter)
  budget_cover_1..2/ covers: leather with a gold frame, sage linen
  budget_stickers/   labels such as Paid, Due and Payday

Re-running keeps each item's version, so raise "version" in its
listing.json by hand when files change, then check and publish with
tool/catalog.py. Needs Pillow, and macOS `sips` for the PDF preview.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_collection as mc  # noqa: E402
import make_planner as mp  # noqa: E402

CATALOG = mc.CATALOG
CID = "budget"
TAGS = ["budget", "finance", "money", "undated", "monthly"]

# Landscape, like a spread on an iPad held sideways.
mp.W, mp.H = 792, 612
W, H = mp.W, mp.H

BROWN = (0.33, 0.24, 0.17)
GOLD = (0.72, 0.58, 0.33)
STYLE = mp.Style(
    ink=(0.17, 0.14, 0.11),
    soft=(0.47, 0.41, 0.35),
    rule=(0.76, 0.71, 0.63),
    accent=BROWN,
    tab=(0.95, 0.92, 0.86),
    on_accent=(1, 0.98, 0.94),
    paper=(1, 0.995, 0.98),
    serif=True,
)

MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]

# Page indexes.
YEAR = 0
MONTH = {m: 1 + m for m in range(12)}
BILLS, SAVINGS, DEBT = 13, 14, 15
PAGE_COUNT = 16

LEFT, RIGHT = 28, W - 28
TOP = H - 66  # below the title bar


def top_bar(p, title, subtitle, current):
    """The title banner, a gold rule, and tabs to every page."""
    p.rect(0, H - 46, W, 46, fill=STYLE.tab)
    p.line(0, H - 46, W, H - 46, rgb=GOLD, width=1.6)
    p.line(0, H - 49, W, H - 49, rgb=BROWN, width=0.6)
    bw = mp.text_width(title, 18) + 30
    p.rect(LEFT, H - 40, bw, 30, fill=BROWN)
    p.text(LEFT + 15, H - 31, title, 18, rgb=STYLE.on_accent, bold=True)
    p.text(LEFT + bw + 12, H - 30, subtitle, 12, rgb=STYLE.soft)

    tabs = [("Year", YEAR)] + [(MONTHS[m][:3], MONTH[m]) for m in range(12)] + [
        ("Bills", BILLS), ("Save", SAVINGS), ("Debt", DEBT)]
    tw, gap = 26.5, 2
    x = RIGHT - len(tabs) * (tw + gap) + gap
    for label, target in tabs:
        on = target == current
        p.rect(x, H - 36, tw, 22, fill=BROWN if on else (1, 1, 1), stroke=None if on else STYLE.rule, width=0.6)
        p.text(x + tw / 2, H - 28, label, 7, rgb=STYLE.on_accent if on else BROWN, bold=on, center=True)
        p.link(x, H - 36, tw, 22, target)
        x += tw + gap


def section_title(p, x, y, title, note=None):
    p.text(x, y, title, 9, rgb=BROWN, bold=True)
    if note:
        p.text(x + mp.text_width(title, 9) + 8, y, note, 7, rgb=STYLE.soft)


def table(p, x, top, w, title, rows, label_w, columns=("Budget", "Actual", "Difference"),
          row_h=13.0, total=True, note=None, label_header=""):
    """A titled table: a header row, one row per label, and a total.
    Returns the y of its bottom edge."""
    section_title(p, x, top - 9, title, note)
    y = top - 14
    cw = (w - label_w) / len(columns)
    p.rect(x, y - row_h, w, row_h, fill=STYLE.tab)
    p.text(x + 4, y - row_h + 4, label_header, 6.5, rgb=STYLE.soft)
    for i, c in enumerate(columns):
        p.text(x + label_w + i * cw + cw / 2, y - row_h + 4, c, 7, rgb=BROWN, bold=True, center=True)
    labels = list(rows) + (["Total"] if total else [])
    bottom = y - row_h * (len(labels) + 1)
    for r, label in enumerate(labels):
        ry = y - row_h * (r + 2)
        if label == "Total":
            p.rect(x, ry, w, row_h, fill=STYLE.tab)
        p.text(x + 4, ry + 4, label, 7.5, rgb=STYLE.ink, bold=label == "Total")
        p.line(x, ry, x + w, ry, width=0.5)
    p.rect(x, bottom, w, y - bottom, stroke=STYLE.rule, width=0.8)
    p.line(x + label_w, y, x + label_w, bottom, width=0.6)
    for i in range(1, len(columns)):
        p.line(x + label_w + i * cw, y, x + label_w + i * cw, bottom, width=0.5)
    return bottom


def lines(p, x0, x1, top, bottom, step=16):
    y = top - step
    while y >= bottom:
        p.line(x0, y, x1, y, width=0.5)
        y -= step


def checkbox_lines(p, x, w, top, count, step):
    for i in range(count):
        y = top - (i + 1) * step
        p.rect(x, y + 2, 8, 8, stroke=STYLE.soft, width=0.8)
        p.line(x + 14, y, x + w, y, width=0.5)


# Pages


def month_page(p, m):
    top_bar(p, "BUDGET", f"{MONTHS[m]}  ·  Year ______", MONTH[m])
    mid = W / 2
    lw = mid - 8 - LEFT  # left column width
    rx, rw = mid + 8, RIGHT - mid - 8

    # Vision and goals, side by side.
    half = (lw - 10) / 2
    section_title(p, LEFT, TOP - 9, "Vision", "what this money is for")
    p.rect(LEFT, TOP - 82, half, 68, stroke=STYLE.rule)
    lines(p, LEFT + 6, LEFT + half - 6, TOP - 14, TOP - 80, step=16)
    gx = LEFT + half + 10
    section_title(p, gx, TOP - 9, "Goals", "key money measures")
    p.rect(gx, TOP - 82, half, 68, stroke=STYLE.rule)
    checkbox_lines(p, gx + 6, half - 12, TOP - 14, 4, 16)

    # The month at a glance.
    y = table(p, LEFT, TOP - 92, lw, "Finance", ["Total income", "Total expenses", "Total savings"],
              label_w=110, total=False, label_header="Total")

    # Accounts: balances at the start and end of the month.
    cols = ("Starting balance", "Goal", "Ending balance", "Difference")
    for title, kind in (("Accounts", "Cash / Checking"), ("Accounts", "Savings / Investments"),
                        ("Accounts", "Credit cards / Loans")):
        y = table(p, LEFT, y - 6, lw, title, [""] * 3, label_w=80, columns=cols, total=False,
                  note=kind, label_header="Account")

    section_title(p, LEFT, y - 15, "Notes")
    lines(p, LEFT, LEFT + lw, y - 18, 30, step=15)

    # Income and expenses.
    y = table(p, rx, TOP, rw, "Income", ["Wages / Tips", "Wages / Tips", "Side income", "Interest",
                                         "Dividends", "Gifts", "Reimbursements", "Transfers"],
              label_w=118, label_header="Source", row_h=13.5)
    y = table(p, rx, y - 4, rw, "Expenses", ["Mortgage / Rent", "Auto", "Electricity", "Heating / Cooling",
                                            "Water / Sewer / Trash", "Phone / Internet / TV",
                                            "Maintenance / Repairs"],
              label_w=118, note="home", label_header="Bill", row_h=13.5)
    table(p, rx, y - 4, rw, "Expenses", ["Groceries", "Personal care", "Clothing", "Entertainment",
                                        "Dining out", "Medical", "Fitness / Health",
                                        "Auto / Life / Home insurance", "Education",
                                        "Charity / Donations / Gifts", "Pets", "Vacation / Travel",
                                        "Debt payments"],
          label_w=118, note="daily", label_header="Item", row_h=13.5)


def year_page(p):
    top_bar(p, "BUDGET", "Year at a glance  ·  Year ______", YEAR)
    mid = W * 0.58
    w = mid - 8 - LEFT
    cols = ("Income", "Expenses", "Saved", "Debt paid")
    bottom = table(p, LEFT, TOP, w, "The year", MONTHS, label_w=90, columns=cols,
                   row_h=24, note="tap a month to open it", label_header="Month")
    # Each month's row opens its page.
    for m in range(12):
        ry = TOP - 14 - 24 * (m + 2)
        p.link(LEFT, ry, w, 24, MONTH[m])
    _ = bottom

    rx, rw = mid + 8, RIGHT - mid - 8
    section_title(p, rx, TOP - 9, "This year I want to")
    p.rect(rx, TOP - 150, rw, 136, stroke=STYLE.rule)
    checkbox_lines(p, rx + 8, rw - 16, TOP - 16, 7, 18)

    section_title(p, rx, TOP - 172, "Savings goal", "shade a box for every 5%")
    p.text(rx, TOP - 190, "Goal  ____________   Target  $__________", 8, rgb=STYLE.soft)
    bw = (rw - 9 * 3) / 10
    for row in range(2):
        for i in range(10):
            p.rect(rx + i * (bw + 3), TOP - 222 - row * (bw * 0.6 + 4), bw, bw * 0.6, stroke=GOLD, width=0.8)

    table(p, rx, TOP - 262, rw, "Big purchases", [""] * 6, label_w=90,
          columns=("Cost", "Saved", "By"), total=False, label_header="Item", row_h=16)


def bills_page(p):
    top_bar(p, "BILLS", "Tick when paid  ·  Year ______", BILLS)
    label_w, fixed = 120, ("Due", "Amount")
    cols = fixed + tuple(m[:1] for m in MONTHS)
    w = RIGHT - LEFT
    rows = 26
    row_h = 17
    y = TOP - 14
    section_title(p, LEFT, TOP - 9, "Bill tracker")
    fixed_w = 54
    month_w = (w - label_w - fixed_w * 2) / 12
    xs = [LEFT + label_w, LEFT + label_w + fixed_w]
    xs += [LEFT + label_w + fixed_w * 2 + i * month_w for i in range(12)]
    p.rect(LEFT, y - row_h, w, row_h, fill=STYLE.tab)
    p.text(LEFT + 4, y - row_h + 5, "Bill", 7, rgb=BROWN, bold=True)
    for i, c in enumerate(cols):
        cw = fixed_w if i < 2 else month_w
        p.text(xs[i] + cw / 2, y - row_h + 5, MONTHS[i - 2][:3] if i >= 2 else c, 7, rgb=BROWN, bold=True, center=True)
    for r in range(rows):
        ry = y - row_h * (r + 2)
        p.line(LEFT, ry, RIGHT, ry, width=0.5)
        for i in range(12):
            cx = xs[2 + i] + month_w / 2
            p.rect(cx - 4, ry + 4.5, 8, 8, stroke=STYLE.soft, width=0.6)
    bottom = y - row_h * (rows + 1)
    p.rect(LEFT, bottom, w, y - bottom, stroke=STYLE.rule)
    for x in xs:
        p.line(x, y, x, bottom, width=0.5)


def savings_page(p):
    top_bar(p, "SAVINGS", "Shade a box for every 5% saved", SAVINGS)
    gap = 14
    cw = (RIGHT - LEFT - gap) / 2
    ch = (TOP - 30 - gap) / 2
    for i in range(4):
        x = LEFT + (i % 2) * (cw + gap)
        top = TOP - (i // 2) * (ch + gap)
        p.rect(x, top - ch, cw, ch, stroke=STYLE.rule)
        p.rect(x, top - 20, cw, 20, fill=STYLE.tab)
        p.text(x + 8, top - 14, f"Goal {i + 1}", 9, rgb=BROWN, bold=True)
        p.text(x + 8, top - 36, "For  ____________________", 8, rgb=STYLE.soft)
        p.text(x + cw / 2 + 10, top - 36, "Target $_________   By ________", 8, rgb=STYLE.soft)
        bw = (cw - 16 - 9 * 3) / 10
        for row in range(2):
            for k in range(10):
                p.rect(x + 8 + k * (bw + 3), top - 64 - row * 18, bw, 14, stroke=GOLD, width=0.8)
        # Deposits.
        ty = top - 92
        p.text(x + 8, ty, "Date", 7, rgb=BROWN, bold=True)
        p.text(x + 80, ty, "Added", 7, rgb=BROWN, bold=True)
        p.text(x + 160, ty, "Total saved", 7, rgb=BROWN, bold=True)
        lines(p, x + 8, x + cw - 8, ty - 2, top - ch + 6, step=15)


def debt_page(p):
    top_bar(p, "DEBT", "Smallest balance first", DEBT)
    w = RIGHT - LEFT
    y = table(p, LEFT, TOP, w, "What I owe", [""] * 8, label_w=170,
              columns=("Balance", "Interest rate", "Minimum", "Due day", "Paid off on"),
              total=True, label_header="Debt", row_h=17)
    table(p, LEFT, y - 8, w, "Payments", [""] * 17, label_w=170,
          columns=("Date", "Paid", "Extra", "New balance", "Left to go"),
          total=False, label_header="Debt", row_h=15)


def planner():
    mp.use_style(STYLE)
    pages = [mp.Page() for _ in range(PAGE_COUNT)]
    year_page(pages[YEAR])
    for m in range(12):
        month_page(pages[MONTH[m]], m)
    bills_page(pages[BILLS])
    savings_page(pages[SAVINGS])
    debt_page(pages[DEBT])
    spec = {
        "mode": "notebook",
        "sections": [
            {"title": "Year", "pages": [{"pdfPage": YEAR + 1, "title": "Year at a glance"}]},
            {"title": "Months", "pages": [{"pdfPage": MONTH[m] + 1, "title": MONTHS[m], "month": m + 1} for m in range(12)]},
            {"title": "Trackers", "pages": [
                {"pdfPage": BILLS + 1, "title": "Bills"},
                {"pdfPage": SAVINGS + 1, "title": "Savings goals"},
                {"pdfPage": DEBT + 1, "title": "Debt payoff"},
            ]},
        ],
    }
    return pages, spec


# Covers and stickers


def leather_cover(base, title_ink, frame):
    w, h = mc.COVER
    im = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(im)
    # A faint grain, so it reads as leather or linen rather than flat color.
    import random
    rnd = random.Random(str(base))
    for _ in range(9000):
        x, y = rnd.randrange(w), rnd.randrange(h)
        tone = mc.mix(base, (0, 0, 0) if rnd.random() < 0.5 else (255, 255, 255), rnd.uniform(0.03, 0.08))
        d.point((x, y), fill=tone)
    d.rectangle((100, 100, w - 100, h - 100), outline=frame, width=8)
    d.rectangle((126, 126, w - 126, h - 126), outline=frame, width=3)
    for cx, cy in ((126, 126), (w - 126, 126), (126, h - 126), (w - 126, h - 126)):
        d.rectangle((cx - 18, cy - 18, cx + 18, cy + 18), fill=frame)
    big, small = mc.font(220), mc.font(70, bold=False)
    tw = d.textlength("BUDGET", font=big)
    d.text(((w - tw) / 2, h * 0.36), "BUDGET", font=big, fill=title_ink)
    d.line((w * 0.3, h * 0.5, w * 0.7, h * 0.5), fill=frame, width=6)
    sub = "planner"
    sw = d.textlength(sub, font=small)
    d.text(((w - sw) / 2, h * 0.52), sub, font=small, fill=title_ink)
    # The elastic strap.
    d.rectangle((w - 230, 0, w - 180, h), fill=mc.mix(base, (0, 0, 0), 0.35))
    return im


def write_covers():
    gold = (196, 160, 92)
    for i, (name, base, ink) in enumerate((
        ("Leather", (92, 64, 45), gold),
        ("Sage", (122, 138, 112), (250, 246, 236)),
    ), start=1):
        folder = CATALOG / f"{CID}_cover_{i}"
        folder.mkdir(parents=True, exist_ok=True)
        im = leather_cover(base, ink, gold if i == 1 else mc.mix(base, (255, 255, 255), 0.55))
        im.save(folder / "cover.webp", "WEBP", quality=86)
        im.resize((384, 512)).save(folder / "preview.webp", "WEBP", quality=86)
        mc.write_listing(folder, {
            "kind": "cover",
            "name": f"Budget {name}",
            "version": 1,
            "unlock": {},
            "collectionId": CID,
            "category": "covers",
            "color": "#%02X%02X%02X" % base,
            "tags": TAGS,
        })


STICKERS = ["Paid", "Due", "Payday", "Saved!", "No spend", "Over budget", "Bill", "Goal met"]


def write_stickers():
    folder = CATALOG / f"{CID}_stickers"
    (folder / "stickers").mkdir(parents=True, exist_ok=True)
    for old in (folder / "stickers").glob("*.webp"):
        old.unlink()
    palette = [(214, 196, 160), (190, 205, 180), (235, 205, 190), (205, 195, 220)]
    ink = (70, 50, 35)
    entries = []
    for k, word in enumerate(STICKERS):
        name = "label_" + word.lower().replace("!", "").replace(" ", "_")
        mc.sticker_label(word, palette[k % len(palette)], ink).save(
            folder / "stickers" / f"{name}.webp", "WEBP", lossless=True)
        entries.append({"file": f"stickers/{name}.webp", "name": word})
    (folder / "stickers.json").write_text(json.dumps({"stickers": entries}, indent=2) + "\n")
    prev = Image.new("RGB", (512, 384), (255, 253, 248))
    for n, e in enumerate(entries):
        with Image.open(folder / e["file"]) as s:
            s.thumbnail((230, 86))
            x, y = 16 + (n % 2) * 248, 14 + (n // 2) * 92
            prev.paste(s, (x + (230 - s.width) // 2, y), s)
    prev.save(folder / "preview.webp", "WEBP", quality=88)
    mc.write_listing(folder, {
        "kind": "stickers",
        "name": "Budget Stickers",
        "version": 1,
        "unlock": {},
        "collectionId": CID,
        "category": "stickers",
        "tags": TAGS,
    })


def write_planner():
    folder = CATALOG / f"{CID}_planner"
    folder.mkdir(parents=True, exist_ok=True)
    pages, spec = planner()
    mp.write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec, indent=2) + "\n")
    # The preview shows a month, the page people buy it for.
    one = folder / "month.pdf"
    month = pages[MONTH[0]]
    links, month.links = month.links, []
    mp.write_pdf([month], one)
    month.links = links
    mp.write_preview(one, folder / "preview.webp")
    one.unlink()
    mc.write_listing(folder, {
        "kind": "template",
        "name": "Monthly Budget Planner",
        "version": 1,
        "unlock": {},
        "collectionId": CID,
        "category": "planners",
        "tags": TAGS,
    })
    return len(pages)


def write_collection():
    folder = CATALOG / CID
    folder.mkdir(parents=True, exist_ok=True)
    prev = Image.new("RGB", (512, 320), (240, 233, 220))
    with Image.open(CATALOG / f"{CID}_cover_1" / "cover.webp") as c:
        prev.paste(c.resize((180, 240)), (20, 40))
    with Image.open(CATALOG / f"{CID}_planner" / "preview.webp") as p:
        p = p.convert("RGB")
        p.thumbnail((290, 240))
        prev.paste(p, (212, (320 - p.height) // 2))
    prev.save(folder / "preview.webp", "WEBP", quality=88)
    mc.write_listing(folder, {
        "kind": "collection",
        "name": "Budget",
        "version": 1,
        "unlock": {"pro": True, "products": [f"pack_{CID}"]},
        "tags": TAGS,
    })


def main():
    count = write_planner()
    write_covers()
    write_stickers()
    write_collection()
    print(f"{CID}: planner ({count} pages), 2 covers, {len(STICKERS)} stickers")


if __name__ == "__main__":
    main()
