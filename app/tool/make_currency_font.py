"""Builds the BankPop money sign as a one-glyph font.

The app prints amounts as text everywhere - wallets, ledgers, deeds, dialogs and
the board picture that is painted with a `TextPainter` rather than widgets. A
font glyph is the only thing that reaches all of those with one change: the sign
lives at U+E000, the app writes that character, and every `Text` in the app
draws it with no widget wrapper and no layout change.

Geometry is the heavy-bar B from `design/currency-glyphs.html` (the "Heavy Bar
B" iteration): a bold B with two bars hanging off its stem. The strokes of that
drawing are turned into filled outlines here, because a font stores filled
contours, not strokes.

Run it from the `app` directory:

    python3 tool/make_currency_font.py

Requires `fonttools` (a build-time tool only - the app itself needs nothing).
"""

from __future__ import annotations

import math
import os

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

# --- The drawing, in the 100-unit box the icon set uses ---------------------

STROKE = 20.0          # half-width 10, the weight of the sign
DESIGN_TOP = 6.0       # top of the stem's round cap
DESIGN_BOTTOM = 94.0   # bottom of the stem's round cap
DESIGN_LEFT = 4.0      # left end of the bars
DESIGN_RIGHT = 86.0    # right of the lower bowl

UPM = 1000
CAP_HEIGHT = 700.0     # the sign is as tall as a capital
LEFT_BEARING = 60.0
RIGHT_BEARING = 60.0

CODEPOINT = 0xE000

SCALE = CAP_HEIGHT / (DESIGN_BOTTOM - DESIGN_TOP)


def _x(value: float) -> float:
    return (value - DESIGN_LEFT) * SCALE + LEFT_BEARING


def _y(value: float) -> float:
    # Font y grows upwards, the drawing's grows downwards.
    return CAP_HEIGHT - (value - DESIGN_TOP) * SCALE


# Each stroke of the B as a centreline: a list of (kind, points) segments.
UPPER_BOWL = [
    ("line", [(37, 16), (57, 16)]),
    ("cubic", [(57, 16), (71, 16), (79, 23), (79, 32)]),
    ("cubic", [(79, 32), (79, 41), (71, 48), (57, 48)]),
    ("line", [(57, 48), (37, 48)]),
]

LOWER_BOWL = [
    ("line", [(37, 48), (61, 48)]),
    ("cubic", [(61, 48), (77, 48), (86, 57), (86, 67)]),
    ("cubic", [(86, 67), (86, 77), (77, 84), (61, 84)]),
    ("line", [(61, 84), (37, 84)]),
]


def _sample(segments, steps: int = 24):
    """Points along a centreline, in drawing units."""
    pts = [segments[0][1][0]]
    for kind, coords in segments:
        start = pts[-1]
        if kind == "line":
            pts.append(coords[1])
        else:
            c1, c2, end = coords[1], coords[2], coords[3]
            for i in range(1, steps + 1):
                t = i / steps
                mt = 1 - t
                x = (mt ** 3) * start[0] + 3 * (mt ** 2) * t * c1[0] \
                    + 3 * mt * (t ** 2) * c2[0] + (t ** 3) * end[0]
                y = (mt ** 3) * start[1] + 3 * (mt ** 2) * t * c1[1] \
                    + 3 * mt * (t ** 2) * c2[1] + (t ** 3) * end[1]
                pts.append((x, y))
    return pts


def _offset(pts, distance: float):
    """The centreline pushed out by `distance` along its normal."""
    out = []
    half = STROKE / 2
    for i, (x, y) in enumerate(pts):
        if i == 0:
            tx, ty = pts[1][0] - x, pts[1][1] - y
        elif i == len(pts) - 1:
            tx, ty = x - pts[-2][0], y - pts[-2][1]
        else:
            tx, ty = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        length = math.hypot(tx, ty) or 1.0
        # Normal pointing right of travel: (+ty, -tx) / length.
        nx, ny = ty / length, -tx / length
        out.append((x + nx * half * (distance / half), y + ny * half * (distance / half)))
    return out


def _stroke_contour(segments):
    """One closed contour for a stroked centreline (its outer edge, then its
    inner edge reversed)."""
    pts = _sample(segments)
    outer = _offset(pts, STROKE / 2)
    inner = _offset(pts, -STROKE / 2)
    return outer + list(reversed(inner))


def _rounded_rect(x0: float, y0: float, x1: float, y1: float, radius: float):
    """A rounded rectangle as a contour, in drawing units.

    `y0` is the larger drawing y (the lower edge on screen), matching how the
    rest of this file talks about the drawing.
    """
    r = radius
    top, bottom = y1, y0
    pts = []
    corners = (
        (x1 - r, top + r, -90, 0),      # top right
        (x1 - r, bottom - r, 0, 90),    # bottom right
        (x0 + r, bottom - r, 90, 180),  # bottom left
        (x0 + r, top + r, 180, 270),    # top left
    )
    for cx, cy, start, end in corners:
        for i in range(0, 9):
            angle = math.radians(start + (end - start) * i / 8)
            pts.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    return pts


def build(path: str) -> None:
    contours = [
        # The stem of the B, with round ends.
        _rounded_rect(37 - 10, 84 + 10, 37 + 10, 16 - 10, 10),
        # The two bars, hanging off the left of the stem.
        _rounded_rect(4, 47, 40, 35, 6),
        _rounded_rect(4, 71, 40, 59, 6),
        # The bowls.
        _stroke_contour(UPPER_BOWL),
        _stroke_contour(LOWER_BOWL),
    ]

    pen = TTGlyphPen(None)
    for contour in contours:
        first = contour[0]
        pen.moveTo((round(_x(first[0])), round(_y(first[1]))))
        for point in contour[1:]:
            pen.lineTo((round(_x(point[0])), round(_y(point[1]))))
        pen.closePath()
    glyph = pen.glyph()

    advance = DESIGN_RIGHT - DESIGN_LEFT
    units = advance * SCALE + LEFT_BEARING + RIGHT_BEARING

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder([".notdef", "bankpop"])
    fb.setupCharacterMap({CODEPOINT: "bankpop"})
    fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "bankpop": glyph})
    fb.setupHorizontalMetrics({".notdef": (units, 0), "bankpop": (units, round(LEFT_BEARING))})
    fb.setupHorizontalHeader(ascent=round(CAP_HEIGHT), descent=-round(UPM - CAP_HEIGHT))
    fb.setupNameTable({
        "familyName": "Bankpop Mark",
        "styleName": "Regular",
        "psName": "BankpopMark-Regular",
        "version": "Version 1.000",
        "uniqueFontIdentifier": "BankpopMark-Regular;1.000",
    })
    fb.setupOS2(
        sTypoAscender=round(CAP_HEIGHT),
        sTypoDescender=-round(UPM - CAP_HEIGHT),
        sTypoLineGap=0,
        usWinAscent=round(CAP_HEIGHT),
        usWinDescent=round(UPM - CAP_HEIGHT),
        sxHeight=round(CAP_HEIGHT * 0.5),
        sCapHeight=round(CAP_HEIGHT),
    )
    fb.setupPost()
    fb.setupMaxp()
    fb.save(path)
    print(f"wrote {path} ({len(contours)} contours, advance {units:.0f})")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    build(os.path.join(here, "..", "assets", "fonts", "BankpopMark.ttf"))
