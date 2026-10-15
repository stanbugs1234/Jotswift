"""Creative pages: storyboards, comics, sketching, music and lettering."""

import math

from layouts.kit import *  # noqa: F401,F403


def storyboard_wide():
    p = page("Storyboard", "Project  ____________________   Scene  ______")
    w = RIGHT - LEFT - 170
    h = w * 9 / 16
    y = TOP - 44
    for i in range(3):
        frame(p, LEFT, y - h, w, h)
        p.text(LEFT, y - h - 14, f"Shot {i + 1}", 8, rgb=s().soft, bold=True)
        x = LEFT + w + 14
        for k, name in enumerate(("Action", "Dialogue", "Camera")):
            p.text(x, y - 12 - k * (h / 3), name, 8, rgb=s().accent, bold=True)
            lines(p, x, RIGHT, y - 30 - k * (h / 3), 2, gap=16)
        y -= h + 30
    return p, "Storyboard (3 wide)"


def storyboard_43():
    p = page("Storyboard", "Project  ____________________   Scene  ______")
    xs, w = columns(p, LEFT, RIGHT, 3, gap=14)
    h = w * 3 / 4
    y = TOP - 44
    for r in range(4):
        for c, x in enumerate(xs):
            frame(p, x, y - h, w, h)
            p.text(x, y - h - 12, str(r * 3 + c + 1), 8, rgb=s().soft, bold=True)
            lines(p, x + 12, x + w, y - h - 12, 2, gap=14)
        y -= h + 46
    return p, "Storyboard (12 frames, 4:3)"


def _panels(title, rows):
    """Comic panels: [rows] is a list of (height share, [width shares])."""
    def make():
        p = page(title, False)
        gutter = 10
        top, bottom = TOP - 26, BOTTOM
        total = sum(h for h, _ in rows)
        avail = top - bottom - gutter * (len(rows) - 1)
        y = top
        for h_share, widths in rows:
            h = avail * h_share / total
            wavail = RIGHT - LEFT - gutter * (len(widths) - 1)
            x = LEFT
            for share in widths:
                w = wavail * share / sum(widths)
                frame(p, x, y - h, w, h, width=2)
                x += w + gutter
            y -= h + gutter
        return p, title
    return make


comic_six = _panels("Comic: six panels", [(1, [1, 1]), (1, [1, 1]), (1, [1, 1])])
comic_mixed = _panels("Comic: mixed", [(1, [1]), (1.1, [1, 1.4]), (1, [1.2, 1, 1])])
comic_splash = _panels("Comic: splash", [(2.4, [1]), (1, [1, 1, 1])])


def sketch():
    p = page("", False)
    p.line(LEFT, TOP + 6, LEFT + 260, TOP + 6, rgb=s().rule)
    p.text(LEFT, TOP + 10, "Title", 8, rgb=s().soft)
    p.line(RIGHT - 160, TOP + 6, RIGHT, TOP + 6, rgb=s().rule)
    p.text(RIGHT - 160, TOP + 10, "Date", 8, rgb=s().soft)
    frame(p, LEFT, BOTTOM, RIGHT - LEFT, TOP - 14 - BOTTOM, width=1)
    return p, "Sketch page"


def guitar_tab():
    p = page("Guitar tab", "Song  ____________________   Tuning  ________")
    y = TOP - 60
    while y - 5 * 9 > BOTTOM:
        for k in range(6):
            p.line(LEFT + 16, y - k * 9, RIGHT, y - k * 9, rgb=s().soft, width=0.6)
            p.text(LEFT, y - k * 9 - 3, "eBGDAE"[k], 7, rgb=s().soft, bold=True)
        p.line(LEFT + 16, y, LEFT + 16, y - 45, rgb=s().ink, width=1.2)
        p.line(RIGHT, y, RIGHT, y - 45, rgb=s().ink, width=1.2)
        y -= 45 + 44
    return p, "Guitar tab"


def chord_charts():
    p = page("Chords", "Song  ____________________")
    cols, rows = 5, 4
    xs, w = columns(p, LEFT, RIGHT, cols, gap=26)
    fret_h, frets = 20, 5
    y = TOP - 60
    for r in range(rows):
        for x in xs:
            p.line(x, y - 14, x + w, y - 14)
            gx0, gw = x + 8, w - 16
            for k in range(6):
                gx = gx0 + k * gw / 5
                p.line(gx, y - 30, gx, y - 30 - frets * fret_h, rgb=s().soft, width=0.7)
            for f in range(frets + 1):
                p.line(gx0, y - 30 - f * fret_h, gx0 + gw, y - 30 - f * fret_h, rgb=s().soft,
                       width=1.8 if f == 0 else 0.7)
        y -= 30 + frets * fret_h + 30
    return p, "Chord charts"


def handwriting_practice():
    p = page("Handwriting practice", "Letters or words  ________________")
    unit = 9
    y = TOP - 56
    while y - 4 * unit > BOTTOM:
        p.line(LEFT, y, RIGHT, y, rgb=s().soft, width=0.8)
        p.color(s().rule, stroke=True)
        p.ops.append(f"[4 3] 0 d 0.7 w {LEFT:.1f} {y - 1.5 * unit:.1f} m {RIGHT:.1f} {y - 1.5 * unit:.1f} l S [] 0 d")
        p.line(LEFT, y - 3 * unit, RIGHT, y - 3 * unit, rgb=s().accent, width=1)
        p.line(LEFT, y - 4 * unit, RIGHT, y - 4 * unit, rgb=tint(s().rule, 0.4), width=0.5)
        y -= 4 * unit + 18
    return p, "Handwriting practice"


def calligraphy_practice():
    p = page("Lettering practice", "Style  ________________   Nib  ________")
    unit = 11
    slant = math.tan(math.radians(35))
    y = TOP - 56
    while y - 4 * unit > BOTTOM:
        for k, (width, rgb_) in enumerate(((0.7, s().rule), (0.9, s().soft), (1.1, s().accent), (0.5, s().rule))):
            yy = y - (0, 1.5, 3, 4)[k] * unit
            p.line(LEFT, yy, RIGHT, yy, rgb=rgb_, width=width)
        dx = 4 * unit * slant
        x = LEFT
        while x + dx < RIGHT:
            p.line(x, y - 4 * unit, x + dx, y, rgb=tint(s().rule, 0.4), width=0.4)
            x += 2 * unit
        y -= 4 * unit + 20
    return p, "Lettering practice"


LAYOUTS = [storyboard_wide, storyboard_43, comic_six, comic_mixed, comic_splash, sketch, guitar_tab, chord_charts,
           handwriting_practice, calligraphy_practice]
