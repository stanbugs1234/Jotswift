"""Free starter pages: a checklist, a simple day, margin notes, a storyboard
and a weekly to-do."""

from layouts.kit import *  # noqa: F401,F403


def checklist():
    p = page("Checklist")
    checkbox_rows(p, LEFT, RIGHT, TOP - 60, 22, gap=29)
    return p, "Checklist"


def simple_day():
    p = page("Today")
    label(p, LEFT, TOP - 56, "Top priorities")
    numbered(p, LEFT, RIGHT, TOP - 82, 3, gap=28)
    label(p, LEFT, TOP - 186, "To-do")
    checkbox_rows(p, LEFT, RIGHT, TOP - 212, 8)
    label(p, LEFT, TOP - 452, "Notes")
    lines(p, LEFT, RIGHT, TOP - 476, 8)
    return p, "Simple day"


def margin_notes():
    p = page("Notes", "Topic  ________________________   Date  ____________")
    margin = LEFT + 70
    p.line(margin, TOP - 40, margin, BOTTOM, rgb=tint(s().accent, 0.5), width=1)
    lines(p, LEFT, RIGHT, TOP - 62, 24, gap=26)
    return p, "Notes with margin"


def storyboard():
    p = page("Storyboard", "Project  ____________________   Scene  ______")
    cols, rows = 2, 3
    xs, w = columns(p, LEFT, RIGHT, cols, gap=18)
    h = w * 9 / 16
    y = TOP - 48
    for r in range(rows):
        for c in range(cols):
            frame(p, xs[c], y - h, w, h)
            p.text(xs[c], y - h - 14, f"{r * cols + c + 1}", 8, rgb=s().soft, bold=True)
            lines(p, xs[c] + 14, xs[c] + w, y - h - 14, 3, gap=16)
        y -= h + 72
    return p, "Storyboard (6 frames)"


def weekly_todo():
    p = page("This week's to-do", "Week of  ________________")
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Later"]
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    bh = (TOP - 44 - BOTTOM - 3 * 12) / 4
    for i, d in enumerate(days):
        x = xs[i % 2]
        y = TOP - 44 - (i // 2 + 1) * bh - (i // 2) * 12
        box(p, x, y, w, bh, d)
        checkbox_rows(p, x + 10, x + w - 10, y + bh - 44, int((bh - 40) / 26), gap=26)
    return p, "Weekly to-do"


LAYOUTS = [checklist, simple_day, margin_notes, storyboard, weekly_todo]
