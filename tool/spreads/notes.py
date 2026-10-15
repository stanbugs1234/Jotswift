"""Notes spreads: lined, dot grid, grid, blank and Cornell across both
pages."""

from spreads.kit import *  # noqa: F401,F403


def lined(sp):
    for x0, x1 in (sp.left, sp.right):
        caps(sp.page, x0, TOP - 6, "Date  ________")
        ruled(sp.page, x0, x1, TOP - 10, BOTTOM + 4, 17)


def dotted(sp):
    for x0, x1 in (sp.left, sp.right):
        dots(sp.page, x0 + 4, BOTTOM + 8, x1 - 4, TOP - 10, 14)


def grid(sp):
    for x0, x1 in (sp.left, sp.right):
        step = 14
        x = x0
        while x <= x1 + 0.1:
            sp.page.line(x, BOTTOM + 4, x, TOP - 8, rgb=S().rule, width=0.4)
            x += step
        y = TOP - 8
        while y >= BOTTOM + 4:
            sp.page.line(x0, y, x1, y, rgb=S().rule, width=0.4)
            y -= step


def blank(sp):
    for x0, x1 in (sp.left, sp.right):
        sp.page.rect(x0, BOTTOM + 4, x1 - x0, TOP - 12 - BOTTOM, stroke=S().rule, width=0.6)


def cornell(sp):
    p = sp.page
    x0, x1 = sp.left
    caps(p, x0, TOP - 6, "Topic  ______________________   Date  ________")
    cue = x0 + (x1 - x0) * 0.3
    p.line(cue, TOP - 14, cue, BOTTOM + 4, rgb=S().accent, width=0.8)
    caps(p, x0, TOP - 24, "Cues")
    ruled(p, cue + 4, x1, TOP - 14, BOTTOM + 4, 17)
    rx0, rx1 = sp.right
    ruled(p, rx0, rx1, TOP - 10, BOTTOM + 110, 17)
    top = panel(p, rx0, BOTTOM + 100, rx1 - rx0, 96, "Summary")
    ruled(p, rx0 + 6, rx1 - 6, top, BOTTOM + 6, 17)


TITLES = {
    lined: "Lined notes",
    dotted: "Dot grid",
    grid: "Grid",
    blank: "Blank",
    cornell: "Cornell notes",
}
