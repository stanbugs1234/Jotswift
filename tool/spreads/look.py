"""The look shared by every spread planner: landscape pages drawn as an open
book (two pages and a binding shadow), a header with the section title,
and coloured tabs down the right edge that link to each section.

A colourway (Classic, Pastel, Neutral) sets the header, lines and tab
colours. Layouts draw into the two halves given by a Spread.
"""

import make_planner as mp
from make_planner import Page, Style, tint

W, H = 792, 612  # landscape US Letter

# Where things go.
TAB_X, TAB_W = W - 30, 22  # the tab column
LEFT_X, RIGHT_X = 18, TAB_X - 10  # the pages, binding in the middle
MID = (LEFT_X + RIGHT_X) / 2
TOP, BOTTOM = H - 44, 18  # below the header, above the bottom edge
GUTTER = 12  # space either side of the binding


def rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


class Colourway:
    def __init__(self, key, name, file, header, ink, soft, rule, box, tabs, paper=(1, 1, 1)):
        self.key, self.name, self.file = key, name, file
        self.header, self.tabs, self.paper = rgb(header), [rgb(t) for t in tabs], paper
        self.style = Style(
            ink=rgb(ink),
            soft=rgb(soft),
            rule=rgb(rule),
            accent=rgb(header),
            tab=rgb(box),
            on_accent=(1, 1, 1),
            paper=paper,
        )


COLOURWAYS = [
    Colourway(
        "classic", "Classic", "template.pdf",
        header="#2C3E66", ink="#28324A", soft="#7C869C", rule="#C9D1DF", box="#EEF2F8",
        tabs=["#8E6CC4", "#5A7BD8", "#3FA7C9", "#3DB39E", "#7BC24A", "#E8C33A",
              "#F29A3A", "#E8604C", "#E2588F", "#A35BB8", "#5F6B8A", "#8A9AB5"],
    ),
    Colourway(
        "pastel", "Pastel", "template_pastel.pdf",
        header="#7E6AAE", ink="#3E3650", soft="#9A8FB0", rule="#E2DAEE", box="#F5F1FB",
        tabs=["#C9B6EC", "#B6C6F2", "#A9DCE8", "#B4E3CE", "#D3EDB0", "#F6E7A6",
              "#F8CFA4", "#F5B5AE", "#F2B5CF", "#DDB9E6", "#C4C9DB", "#D6DEEA"],
        paper=rgb("#FFFDFC"),
    ),
    Colourway(
        "neutral", "Neutral", "template_neutral.pdf",
        header="#7A6552", ink="#3B322B", soft="#9A8C7E", rule="#E2D8CC", box="#F6F1EA",
        tabs=["#9C8B78", "#B9A48A", "#A3B18A", "#7F9172", "#C9A66B", "#D9B98C",
              "#C08A6B", "#A9674E", "#B98C86", "#8C7B8F", "#7E8A8C", "#A6A096"],
        paper=rgb("#FFFCF7"),
    ),
]
COLOURWAY = {c.key: c for c in COLOURWAYS}


class Spread:
    """One landscape page of a planner: the two halves to draw in, and what
    the header and tabs need."""

    def __init__(self, page, planner, section, title, tabs, index_page):
        self.page, self.planner, self.section, self.title = page, planner, section, title
        self.tabs, self.index_page = tabs, index_page  # [(label, first page)], page

    # The two pages, as (x0, x1).
    left = (LEFT_X + 6, MID - GUTTER)
    right = (MID + GUTTER, RIGHT_X - 6)


def text_up(p, x, y, s, size, rgb_, bold=True):
    """Text reading bottom to top, starting at (x, y)."""
    s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    p.color(rgb_)
    font = "F2" if bold else "F1"
    p.ops.append(f"BT /{font} {size} Tf 0 1 -1 0 {x:.1f} {y:.1f} Tm ({s}) Tj ET")


def draw_frame(sp, colourway):
    """The book, binding, header and tabs for [sp]."""
    p, c = sp.page, colourway
    # The open book: a soft page edge and a binding shadow in the middle.
    p.rect(LEFT_X, BOTTOM - 6, RIGHT_X - LEFT_X, H - BOTTOM - 8, stroke=tint(c.style.rule, 0.2), width=0.8)
    for i, a in enumerate((0.75, 0.82, 0.88, 0.93, 0.97)):
        shade = tuple(ch * (1 - (1 - a) * 0.35) for ch in c.paper)
        w = 10 - i * 2
        p.rect(MID - w / 2, BOTTOM - 6, w, H - BOTTOM - 8, fill=shade)
    p.line(MID, BOTTOM - 6, MID, H - 14, rgb=tint(c.style.soft, 0.5), width=0.6)

    # Header: the title on the left page, the planner and index on the right.
    p.text(LEFT_X + 10, H - 32, sp.title.upper(), 12, rgb=c.header, bold=True)
    p.line(LEFT_X + 10, H - 38, MID - GUTTER, H - 38, rgb=c.header, width=1.2)
    p.text(RIGHT_X - 10, H - 32, sp.planner.upper(), 7.5, rgb=c.style.soft, bold=True, right=True)
    if sp.index_page is not None:
        p.text(MID + GUTTER, H - 32, "< INDEX", 7.5, rgb=c.header, bold=True)
        p.link(MID + GUTTER - 4, H - 38, 48, 16, sp.index_page)
    p.line(MID + GUTTER, H - 38, RIGHT_X - 10, H - 38, rgb=c.style.rule, width=0.8)

    # Tabs down the right edge; the current one sticks out.
    n = max(1, len(sp.tabs))
    top, bottom = H - 14, 14
    th = min(52, (top - bottom - (n - 1) * 3) / n)
    for i, (label, target) in enumerate(sp.tabs):
        y = top - (i + 1) * th - i * 3
        on = label == sp.section
        color = c.tabs[i % len(c.tabs)]
        x = TAB_X - (6 if on else 0)
        p.rect(x, y, TAB_W + (6 if on else 0) + 8, th, fill=color)
        size = 6.5 if len(label) > 7 else 7.5
        width = mp.text_width(label.upper(), size)
        text_up(p, x + TAB_W / 2 + 2.5 + (3 if on else 0), y + (th - width) / 2, label.upper(), size,
                (1, 1, 1) if on else tuple(ch * 0.35 for ch in color), bold=True)
        p.link(x, y, TAB_W + 14, th, target)


def new_page(colourway):
    mp.use_size(W, H)
    mp.use_style(colourway.style)
    return Page()
