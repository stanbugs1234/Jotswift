"""Lifestyle pages: travel, home, hobbies and events."""

from layouts.kit import *  # noqa: F401,F403

# Travel


def trip_overview():
    p = page("Trip", False)
    field(p, LEFT, TOP - 24, "Where", LEFT + 300)
    field(p, LEFT + 316, TOP - 24, "When", RIGHT)
    field(p, LEFT, TOP - 50, "Who's coming", RIGHT)
    xs, w = columns(p, LEFT, RIGHT, 2)
    top = TOP - 80
    for x, name, rows in ((xs[0], "Getting there", ("Flight / train", "Depart", "Arrive", "Booking ref")),
                          (xs[1], "Staying", ("Place", "Address", "Check in", "Check out"))):
        box(p, x, top - 150, w, 150, name)
        for k, row in enumerate(rows):
            field(p, x + 10, top - 46 - k * 28, row, x + w - 10, size=9)
    label(p, LEFT, top - 178, "Must see & do")
    checkbox_rows(p, LEFT, RIGHT, top - 202, 7)
    label(p, LEFT, top - 404, "Before we go")
    checkbox_rows(p, LEFT, RIGHT, top - 428, int((top - 428 - BOTTOM) / 28) + 1)
    return p, "Trip overview"


def itinerary():
    p = page("Itinerary", "Trip  ________________")
    bh = (TOP - 40 - BOTTOM - 4 * 10) / 5
    for i in range(5):
        y = TOP - 40 - (i + 1) * bh - i * 10
        p.rect(LEFT, y, 74, bh, fill=s().tab)
        label(p, LEFT + 10, y + bh - 20, f"Day {i + 1}", 11)
        p.text(LEFT + 10, y + bh - 38, "Date", 8, rgb=s().soft)
        p.line(LEFT + 10, y + bh - 54, LEFT + 64, y + bh - 54)
        p.rect(LEFT, y, RIGHT - LEFT, bh, stroke=s().rule)
        for k, part in enumerate(("Morning", "Afternoon", "Evening")):
            ly = y + bh - 22 - k * (bh - 10) / 3
            p.text(LEFT + 86, ly, part, 8.5, rgb=s().soft, bold=True)
            p.line(LEFT + 146, ly - 3, RIGHT - 10, ly - 3)
    return p, "Itinerary"


def packing_list():
    p = page("Packing list", "Trip  ________________")
    groups = [("Clothes", 9), ("Toiletries", 7), ("Tech", 5), ("Documents", 5), ("Extras", 5), ("Last minute", 5)]
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    ys = [TOP - 50, TOP - 50]
    for i, (name, n) in enumerate(groups):
        c = i % 2
        label(p, xs[c], ys[c], name, 11)
        checkbox_rows(p, xs[c], xs[c] + w, ys[c] - 24, n, gap=24)
        ys[c] -= 24 + n * 24 + 20
    return p, "Packing list"


def travel_budget():
    p = page("Travel budget", "Trip  ________________")
    xs, w = columns(p, LEFT, RIGHT, 3)
    for x, name in zip(xs, ("Budget", "Spent", "Left")):
        box(p, x, TOP - 106, w, 62, name)
    table(p, TOP - 126, [("Date", 0), ("What", 0.14), ("Category", 0.52), ("Paid with", 0.72), ("Cost", 0.86)], 20, row_h=27)
    return p, "Travel budget"


def travel_journal():
    p = page("Travel journal", "Place  ________________   Date  ____________")
    p.rect(LEFT, TOP - 260, RIGHT - LEFT, 220, stroke=s().rule)
    p.text(LEFT + 10, TOP - 56, "Photo, ticket or sketch", 9, rgb=s().soft)
    xs, w = columns(p, LEFT, RIGHT, 3)
    for x, name in zip(xs, ("Ate", "Saw", "Loved")):
        box(p, x, TOP - 356, w, 82, name)
    label(p, LEFT, TOP - 384, "Today")
    lines(p, LEFT, RIGHT, TOP - 408, int((TOP - 408 - BOTTOM) / 26) + 1)
    return p, "Travel journal"


# Home


def grocery_list():
    p = page("Groceries", "Week of  ________________")
    groups = ["Fruit & veg", "Meat & fish", "Dairy & eggs", "Bakery", "Pantry", "Frozen", "Drinks", "Household"]
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    bh = (TOP - 44 - BOTTOM - 3 * 12) / 4
    for i, name in enumerate(groups):
        x = xs[i % 2]
        y = TOP - 44 - (i // 2 + 1) * bh - (i // 2) * 12
        box(p, x, y, w, bh, name)
        checkbox_rows(p, x + 10, x + w - 10, y + bh - 42, int((bh - 40) / 24), gap=24)
    return p, "Grocery list"


def recipe():
    p = page("Recipe", False)
    field(p, LEFT, TOP - 24, "Name", RIGHT)
    xs, w = columns(p, LEFT, RIGHT, 4, gap=8)
    for x, name in zip(xs, ("Serves", "Prep", "Cook", "Rating")):
        p.rect(x, TOP - 84, w, 44, fill=tint(s().accent, 0.92))
        p.text(x + 8, TOP - 56, name, 8.5, rgb=s().soft, bold=True)
    stars(p, xs[3] + 12, TOP - 74, 5, 5)
    mid = LEFT + (RIGHT - LEFT) * 0.38
    label(p, LEFT, TOP - 112, "Ingredients")
    checkbox_rows(p, LEFT, mid - 14, TOP - 136, 16, gap=26)
    label(p, mid, TOP - 112, "Method")
    numbered(p, mid, RIGHT, TOP - 136, 16, gap=26)
    label(p, LEFT, 98, "Notes")
    lines(p, LEFT, RIGHT, 76, 2)
    return p, "Recipe card"


def cleaning():
    p = page("Cleaning", "Week of  ________________")
    groups = [("Every day", ["Dishes", "Wipe counters", "Tidy up", "Sweep kitchen"]),
              ("Every week", ["Vacuum", "Mop floors", "Bathrooms", "Change sheets", "Laundry", "Bins out"]),
              ("Every month", ["Fridge", "Oven", "Windows", "Dust high places", "Wash bins"]),
              ("Seasonal", ["Gutters", "Closets", "Deep clean", "Donate"])]
    days = "MTWTFSS"
    y = TOP - 50
    for name, tasks in groups:
        label(p, LEFT, y, name, 11)
        if name == "Every day" or name == "Every week":
            for k, d in enumerate(days):
                p.text(RIGHT - 7 * 20 + k * 20 + 6, y, d, 8, rgb=s().soft, bold=True)
        for t, task in enumerate(tasks):
            ty = y - 24 - t * 24
            p.text(LEFT + 4, ty, task, 9.5)
            p.line(LEFT, ty - 6, RIGHT, ty - 6, rgb=tint(s().rule, 0.3), width=0.5)
            n = 7 if name in ("Every day", "Every week") else 1
            for k in range(n):
                p.rect(RIGHT - n * 20 + k * 20 + 4, ty - 2, 11, 11, stroke=s().soft, width=0.8)
        y -= 24 + len(tasks) * 24 + 16
    return p, "Cleaning schedule"


def chore_chart():
    p = page("Chore chart", "Week of  ________________")
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    name_w = 150
    cw = (RIGHT - LEFT - name_w) / 7
    top = TOP - 44
    p.rect(LEFT, top - 24, RIGHT - LEFT, 24, fill=s().tab)
    label(p, LEFT + 8, top - 16, "Chore  /  who", 9)
    for i, d in enumerate(days):
        label(p, LEFT + name_w + i * cw + cw / 2 - 8, top - 16, d, 9)
    rh = 40
    for r in range(int((top - 24 - BOTTOM) / rh)):
        y = top - 24 - (r + 1) * rh
        p.line(LEFT, y, RIGHT, y)
        for i in range(7):
            circle(p, LEFT + name_w + i * cw + cw / 2, y + rh / 2, 8, s().rule, fill=False, width=0.8)
    return p, "Chore chart"


def garden():
    p = page("Garden", "Season  ________________")
    label(p, LEFT, TOP - 52, "Bed plan")
    dots(p, LEFT, TOP - 300, RIGHT, TOP - 66, 18)
    p.rect(LEFT - 4, TOP - 304, RIGHT - LEFT + 8, 242, stroke=s().rule)
    table(p, TOP - 330, [("Plant", 0), ("Sown", 0.3), ("Sprouted", 0.45), ("Planted out", 0.6), ("Harvest", 0.78)], 12, row_h=27)
    return p, "Garden planner"


# Hobbies


def book_review():
    p = page("Book review", False)
    field(p, LEFT, TOP - 24, "Title", RIGHT)
    field(p, LEFT, TOP - 50, "Author", LEFT + 280)
    field(p, LEFT + 296, TOP - 50, "Genre", RIGHT)
    field(p, LEFT, TOP - 76, "Started", LEFT + 180)
    field(p, LEFT + 196, TOP - 76, "Finished", LEFT + 380)
    stars(p, LEFT + 410, TOP - 74, 5, 7)
    p.rect(LEFT, TOP - 270, 150, 180, stroke=s().rule)
    p.text(LEFT + 10, TOP - 106, "Cover", 9, rgb=s().soft)
    label(p, LEFT + 166, TOP - 106, "In a sentence")
    lines(p, LEFT + 166, RIGHT, TOP - 130, 2)
    label(p, LEFT + 166, TOP - 182, "Characters")
    lines(p, LEFT + 166, RIGHT, TOP - 206, 3)
    label(p, LEFT, TOP - 300, "What I thought")
    lines(p, LEFT, RIGHT, TOP - 324, 9)
    label(p, LEFT, TOP - 576, "Favourite quote")
    p.rect(LEFT, BOTTOM, RIGHT - LEFT, TOP - 590 - BOTTOM, fill=tint(s().accent, 0.92))
    return p, "Book review"


def watch_log():
    p = page("Watched", "Year  ______")
    table(p, TOP - 40, [("Date", 0), ("Title", 0.13), ("Film / show", 0.55), ("Where", 0.72), ("Rating", 0.86)], 22, row_h=28)
    return p, "Movie & TV log"


def wish_list():
    p = page("Wish list")
    table(p, TOP - 40, [("Got it", 0), ("Item", 0.1), ("Where", 0.5), ("Price", 0.72), ("Priority", 0.86)], 22, row_h=28,
          check=True)
    return p, "Wish list"


def gift_list():
    p = page("Gifts", "Occasion  ________________   Budget  ________")
    table(p, TOP - 40, [("Person", 0), ("Idea", 0.24), ("Budget", 0.6), ("Bought", 0.74), ("Wrapped", 0.87)], 20, row_h=30)
    return p, "Gift list"


# Events


def wedding_overview():
    p = page("Our wedding", False)
    xs, w = columns(p, LEFT, RIGHT, 3)
    for x, name in zip(xs, ("Date", "Venue", "Guests")):
        box(p, x, TOP - 92, w, 62, name)
    xs2, w2 = columns(p, LEFT, RIGHT, 2)
    top = TOP - 112
    box(p, xs2[0], top - 210, w2, 210, "Budget")
    for k, row in enumerate(("Total", "Venue", "Food & drink", "Attire", "Photos", "Flowers", "Music")):
        field(p, xs2[0] + 10, top - 44 - k * 24, row, xs2[0] + w2 - 10, size=9)
    box(p, xs2[1], top - 210, w2, 210, "Countdown")
    for k, row in enumerate(("12 months", "9 months", "6 months", "3 months", "1 month", "1 week", "The day")):
        ty = top - 44 - k * 24
        p.rect(xs2[1] + 10, ty - 2, 10, 10, stroke=s().soft, width=1)
        p.text(xs2[1] + 28, ty, row, 9.5)
    label(p, LEFT, top - 236, "To do")
    checkbox_rows(p, LEFT, RIGHT, top - 260, int((top - 260 - BOTTOM) / 28) + 1)
    return p, "Wedding overview"


def guest_list():
    p = page("Guest list", "Event  ________________")
    table(p, TOP - 40, [("RSVP", 0), ("Name", 0.08), ("Address / contact", 0.4), ("Party of", 0.72), ("Meal", 0.84)], 22,
          row_h=28, check=True)
    return p, "Guest list"


def party_planner():
    p = page("Party", False)
    field(p, LEFT, TOP - 24, "Occasion", LEFT + 300)
    field(p, LEFT + 316, TOP - 24, "Date", RIGHT)
    field(p, LEFT, TOP - 50, "Theme", LEFT + 300)
    field(p, LEFT + 316, TOP - 50, "Budget", RIGHT)
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    top = TOP - 76
    for i, (name, n) in enumerate((("Food & drink", 8), ("Decorations", 8), ("Activities", 6), ("Shopping", 6))):
        x = xs[i % 2]
        y = top - (i // 2) * 270
        box(p, x, y - 250, w, 250, name)
        checkbox_rows(p, x + 10, x + w - 10, y - 44, n, gap=26)
    return p, "Party planner"


def vendor_contacts():
    p = page("Vendors", "Event  ________________")
    table(p, TOP - 40, [("Service", 0), ("Name", 0.2), ("Phone / email", 0.44), ("Cost", 0.72), ("Paid", 0.86)], 20, row_h=30)
    return p, "Vendor contacts"


LAYOUTS = [trip_overview, itinerary, packing_list, travel_budget, travel_journal, grocery_list, recipe, cleaning,
           chore_chart, garden, book_review, watch_log, wish_list, gift_list, wedding_overview, guest_list,
           party_planner, vendor_contacts]
