"""Bullet journal kit: index, key, future log, monthly and daily logs,
collections and a tracker, mostly on dot grid."""

from layouts.kit import *  # noqa: F401,F403

MONTHS = ["January", "February", "March", "April", "May", "June",
          "July", "August", "September", "October", "November", "December"]


def _dotted(p, top=TOP - 40):
    dots(p, LEFT, BOTTOM, RIGHT, top, 18)


def index():
    p = page("Index", False)
    top = TOP - 30
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=s().tab)
    label(p, LEFT + 6, top - 15, "Topic", 9)
    label(p, RIGHT - 60, top - 15, "Pages", 9)
    for r in range(int((top - 22 - BOTTOM) / 24)):
        y = top - 22 - (r + 1) * 24
        p.line(LEFT, y, RIGHT, y)
        p.line(RIGHT - 66, y, RIGHT - 66, y + 24, rgb=tint(s().rule, 0.3), width=0.6)
    return p, "Index"


def key():
    p = page("Key", False)
    signs = [(".", "Task"), ("x", "Done"), (">", "Moved"), ("<", "Scheduled"), ("-", "Note"),
             ("o", "Event"), ("*", "Important"), ("!", "Idea")]
    for i, (sign, name) in enumerate(signs):
        y = TOP - 50 - i * 34
        p.rect(LEFT, y - 8, 26, 26, fill=tint(s().accent, 0.9))
        p.text(LEFT + 13, y, sign, 14, rgb=s().accent, bold=True, center=True)
        p.text(LEFT + 40, y, name, 12)
    label(p, LEFT, TOP - 50 - len(signs) * 34 - 10, "My own signs and colours")
    _dotted(p, TOP - 50 - len(signs) * 34 - 30)
    return p, "Key"


def future_log(half):
    """Six months on one page ([half] 1 or 2)."""
    def make():
        p = page("Future log", False)
        months = MONTHS[(half - 1) * 6: half * 6]
        xs, w = columns(p, LEFT, RIGHT, 2, gap=14)
        bh = (TOP - 30 - BOTTOM - 2 * 12) / 3
        for i, m in enumerate(months):
            x = xs[i % 2]
            y = TOP - 30 - (i // 2 + 1) * bh - (i // 2) * 12
            box(p, x, y, w, bh, m)
            dots(p, x + 12, y + 10, x + w - 10, y + bh - 30, 18)
        return p, f"Future log {MONTHS[(half - 1) * 6][:3]}-{months[-1][:3]}"
    return make


def monthly_log():
    p = page("Month", "Month  ________________")
    mid = LEFT + 220
    for d in range(31):
        y = TOP - 54 - d * 20.5
        p.text(LEFT, y, str(d + 1), 8.5, rgb=s().soft, bold=True)
        for k, letter in enumerate("MTWTFSS"):
            p.text(LEFT + 20 + k * 9, y, letter, 7, rgb=tint(s().soft, 0.5))
        p.line(LEFT + 86, y - 3, mid - 16, y - 3)
    p.line(mid, TOP - 40, mid, BOTTOM, rgb=tint(s().accent, 0.5), width=1)
    label(p, mid + 16, TOP - 54, "Tasks")
    dots(p, mid + 16, BOTTOM, RIGHT, TOP - 74, 18)
    return p, "Monthly log"


def daily_log():
    p = page("Daily log", False)
    _dotted(p, TOP - 30)
    return p, "Daily log"


def collection():
    p = page("", False)
    p.line(LEFT, TOP - 4, RIGHT, TOP - 4, rgb=s().accent, width=1.2)
    p.text(LEFT, TOP + 6, "Collection:", 10, rgb=s().soft, bold=True)
    _dotted(p, TOP - 26)
    return p, "Collection"


def tracker():
    p = page("Tracker", "Month  ________________")
    day_grid(p, TOP - 50, [""] * 14, name_w=110, row_h=34)
    return p, "Tracker"


LAYOUTS = [index, key, monthly_log, daily_log, collection, tracker]
future_log_1 = future_log(1)
future_log_2 = future_log(2)
