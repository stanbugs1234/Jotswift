"""Building blocks for page layouts: titled pages, labelled fields, tables,
trackers, frames and dot grids. Everything draws in the current style
(make_planner.use_style), on a US Letter portrait page."""

import math

import make_planner as mp
from make_planner import Page, circle, header, polygon, tint
from page_layouts import LEFT, RIGHT, TOP, box, checkbox_rows, date_line, label, lines

__all__ = [
    "LEFT", "RIGHT", "TOP", "BOTTOM", "s", "page", "Page", "label", "lines", "checkbox_rows", "box",
    "date_line", "field", "fields", "table", "bar", "frame", "dots", "stars", "circle", "tint",
    "day_grid", "numbered", "columns", "header", "polygon",
]

BOTTOM = 40


def s():
    """The current style."""
    return mp.S


def page(title, sub=None, size=30):
    """A page with [title], and a line under it for a date (or [sub])."""
    p = Page()
    header(p, LEFT, TOP, title, size)
    if sub is not False:
        p.text(LEFT, TOP - 22, sub or "Date  ________________", 11, rgb=s().soft)
    return p


def field(p, x, y, name, x_end, size=10):
    """A bold label with a line to write on after it."""
    p.text(x, y, name, size, rgb=s().soft, bold=True)
    start = x + mp.text_width(name, size) + 8
    p.line(start, y - 3, x_end, y - 3)


def fields(p, names, top, gap=28, x0=LEFT, x1=RIGHT):
    """[names] as fields one under another; returns the y below them."""
    for i, name in enumerate(names):
        field(p, x0, top - i * gap, name, x1)
    return top - len(names) * gap


def columns(p, x0, x1, n, gap=14):
    """The left edges and width of [n] columns between [x0] and [x1]."""
    w = (x1 - x0 - gap * (n - 1)) / n
    return [x0 + i * (w + gap) for i in range(n)], w


def table(p, top, cols, rows, row_h=26, x0=LEFT, x1=RIGHT, check=False):
    """A table: a header band, then [rows] ruled rows. [cols] is a list of
    (name, start as a fraction of the width). With [check], each row
    starts with a box. Returns the y of its bottom edge."""
    w = x1 - x0
    p.rect(x0, top - 22, w, 22, fill=s().tab)
    for name, at in cols:
        label(p, x0 + w * at + 6, top - 15, name, 9)
    for _, at in cols[1:]:
        p.line(x0 + w * at, top - 22, x0 + w * at, top - 22 - rows * row_h, rgb=tint(s().rule, 0.3), width=0.6)
    for r in range(rows):
        y = top - 22 - (r + 1) * row_h
        if check:
            p.rect(x0 + 8, y + row_h / 2 - 5, 10, 10, stroke=s().soft, width=1)
        p.line(x0, y, x1, y)
    return top - 22 - rows * row_h


def bar(p, x, y, w, h=12, segments=10):
    """A progress bar of [segments] boxes to colour in."""
    sw = w / segments
    for i in range(segments):
        p.rect(x + i * sw, y, sw, h, stroke=s().rule, width=0.7)


def frame(p, x, y, w, h, width=1.4):
    """A drawing frame with a darker edge."""
    p.rect(x, y, w, h, stroke=tint(s().ink, 0.45), width=width)


def dots(p, x0, y0, x1, y1, step=18):
    """A dot grid filling the box."""
    rgb = tint(s().soft, 0.25)
    y = y1
    while y >= y0:
        x = x0
        while x <= x1:
            circle(p, x, y, 0.7, rgb)
            x += step
        y -= step


def stars(p, x, y, n=5, size=8):
    """[n] outline stars in a row, for ratings."""
    for i in range(n):
        cx = x + i * size * 2.6
        pts = []
        for k in range(10):
            r = size if k % 2 == 0 else size * 0.45
            a = math.pi / 2 + k * math.pi / 5
            pts.append((cx + r * math.cos(a), y + r * math.sin(a)))
        pts.append(pts[0])
        polygon(p, pts, s().soft, fill=False, width=0.8)


def day_grid(p, top, rows, days=31, name_w=60, row_h=None, x0=LEFT, x1=RIGHT, bottom=BOTTOM + 40):
    """Rows of [days] small boxes, each row named from [rows], with day
    numbers along the top. Returns the y of its bottom edge."""
    cw = (x1 - x0 - name_w) / days
    row_h = row_h or min(cw + 6, (top - 14 - bottom) / len(rows))
    for d in range(days):
        p.text(x0 + name_w + d * cw + cw / 2, top, str(d + 1), 6.5, rgb=s().soft, center=True)
    for r, name in enumerate(rows):
        y = top - 10 - (r + 1) * row_h
        if name:
            p.text(x0, y + row_h / 2 - 3, name, 8, rgb=s().accent, bold=True)
        else:
            p.line(x0, y + 2, x0 + name_w - 6, y + 2)
        size = min(cw, row_h) - 2
        for d in range(days):
            p.rect(x0 + name_w + d * cw + (cw - size) / 2, y + (row_h - size) / 2, size, size,
                   stroke=s().rule, width=0.6)
    return top - 10 - len(rows) * row_h


def numbered(p, x0, x1, top, count, gap=26):
    """Numbered lines."""
    for i in range(count):
        y = top - i * gap
        p.text(x0, y + 2, f"{i + 1}.", 9, rgb=s().soft)
        p.line(x0 + 18, y, x1, y)
