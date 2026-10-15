"""Drawing helpers for spread pages, on top of tool/layouts/kit.py. Every
helper draws inside the box it's given, so a layout places panels on the
left and right pages of a Spread."""

import math

import make_planner as mp
from layouts.kit import box, checkbox_rows, circle, columns, dots, lines, table  # noqa: F401
from spreads.look import BOTTOM, TOP, Spread  # noqa: F401

__all__ = [
    "BOTTOM", "TOP", "Spread", "S", "panel", "ruled", "checks", "mini_month", "day_columns",
    "habit_grid", "split", "table", "dots", "lines", "columns", "circle", "caps", "math", "mp",
]


def S():
    return mp.S


def caps(p, x, y, text, size=7, rgb=None):
    p.text(x, y, text.upper(), size, rgb=rgb or S().accent, bold=True)


def panel(p, x, y_top, w, h, title=None):
    """A box with a shaded title strip; returns the y just under the strip."""
    p.rect(x, y_top - h, w, h, stroke=S().rule, width=0.7)
    if not title:
        return y_top - 4
    p.rect(x, y_top - 15, w, 15, fill=S().tab)
    p.line(x, y_top - 15, x + w, y_top - 15, rgb=S().rule, width=0.6)
    caps(p, x + 6, y_top - 11, title)
    return y_top - 15


def ruled(p, x0, x1, top, bottom, gap=16):
    """Lines from [top] down to [bottom]."""
    y = top - gap
    while y >= bottom + 2:
        p.line(x0, y, x1, y, rgb=S().rule, width=0.5)
        y -= gap


def checks(p, x0, x1, top, bottom, gap=16):
    """Checkbox rows from [top] down to [bottom]."""
    y = top - gap
    while y >= bottom + 2:
        p.rect(x0, y + 2, 7, 7, stroke=S().soft, width=0.7)
        p.line(x0 + 11, y + 1, x1, y + 1, rgb=S().rule, width=0.5)
        y -= gap


def split(x0, x1, *shares, gap=8):
    """[x0]-[x1] divided by [shares], as (left, right) pairs."""
    total = sum(shares)
    width = x1 - x0 - gap * (len(shares) - 1)
    out, x = [], x0
    for s in shares:
        w = width * s / total
        out.append((x, x + w))
        x += w + gap
    return out


def mini_month(p, x, y_top, w, h, title="Month"):
    """An undated month: weekday letters and a 6 x 7 grid to number."""
    top = panel(p, x, y_top, w, h, title)
    cw = w / 7
    for i, d in enumerate("MTWTFSS"):
        p.text(x + i * cw + cw / 2, top - 9, d, 6, rgb=S().soft, bold=True, center=True)
    rh = (top - 12 - (y_top - h)) / 6
    for r in range(1, 6):
        p.line(x, top - 12 - r * rh, x + w, top - 12 - r * rh, rgb=S().rule, width=0.4)
    for c in range(1, 7):
        p.line(x + c * cw, top - 12, x + c * cw, y_top - h, rgb=S().rule, width=0.4)


def day_columns(p, x0, x1, top, bottom, labels, gap=14, header=15):
    """Columns with a shaded heading each and ruled lines below."""
    n = len(labels)
    cw = (x1 - x0) / n
    for i, label in enumerate(labels):
        x = x0 + i * cw
        p.rect(x, bottom, cw, top - bottom, stroke=S().rule, width=0.6)
        p.rect(x, top - header, cw, header, fill=S().tab)
        caps(p, x + 4, top - header + 4.5, label, 6.5)
        p.text(x + cw - 4, top - header + 4.5, "___", 6, rgb=S().soft, right=True)
        ruled(p, x + 3, x + cw - 3, top - header, bottom, gap)


def habit_grid(p, x, y_top, w, h, title, rows, cols=7, col_labels="MTWTFSS"):
    """Named rows with a box per day (or per [cols])."""
    top = panel(p, x, y_top, w, h, title)
    name_w = w * 0.42
    cw = (w - name_w - 4) / cols
    for i in range(cols):
        label = col_labels[i] if i < len(col_labels) else str(i + 1)
        p.text(x + name_w + i * cw + cw / 2, top - 9, label, 5.5, rgb=S().soft, bold=True, center=True)
    rh = (top - 12 - (y_top - h) - 2) / rows
    for r in range(rows):
        y = top - 12 - (r + 1) * rh
        p.line(x + 4, y + 2, x + name_w - 4, y + 2, rgb=S().rule, width=0.5)
        s = min(cw, rh) - 3
        for i in range(cols):
            p.rect(x + name_w + i * cw + (cw - s) / 2, y + (rh - s) / 2, s, s, stroke=S().rule, width=0.5)
