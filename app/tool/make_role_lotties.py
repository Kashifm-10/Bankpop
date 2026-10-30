"""Puts BankPop's money sign into the two role animations.

`player_role.json` (the player's seat) and `bank_role.json` (the banker's) are
drawn with a **dollar** on the coins and the notes: the art predates the app's
own sign. The animations themselves are kept exactly as they are - the coins
still spin, the notes still fly - and only the glyph drawn on them is swapped
for the heavy-bar B, so the artwork says the same money the prices do.

The replacement is the same drawing the font uses: `_sign()` from
`make_currency_font.py`, as five closed outlines (stem, the two bars and the two
bowls). Five outlines rather than one silhouette, because a Lottie shape path is
a single contour and the letter's counters are holes in it - drawn separately,
the pieces fill to exactly the glyph.

Which path is the dollar is named below rather than guessed at: the note's is
`Path 3` in the `Money` layers, the coin's is `Path 3` in the `coin Outlines`
layers of the two precomps. The script stops if it does not find them all, so a
re-exported animation fails loudly instead of leaving a dollar behind.

Run it from the `app` directory:

    python tool/make_role_lotties.py
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from make_currency_font import _sign  # noqa: E402  (the font tool's own drawing)

# The heavy cut: stroke 20, 12-high bars - the sign the app shows on prices.
CONTOURS = _sign(stroke=20.0, bar_height=12.0, bar_radius=6.0)

# Where the dollar hides in each file. A layer name matches every layer that
# starts with it, so one entry covers all six notes.
TARGETS: dict[str, list[tuple[str, str, str]]] = {
    "bank_role.json": [("Money", "Group 4", "Path 3")],
    "player_role.json": [
        ("coin Outlines 16", "Group 1", "Path 3"),
        ("coin Outlines 18", "Group 1", "Path 3"),
    ],
}

# How much wider than the dollar the sign may get. A letter is fatter than a
# dollar's stem, so the sign is fitted by height and then held back from
# spilling over the artwork it is printed on.
WIDTH_LIMIT = 1.9


def _bbox(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def _sign_shape(target):
    """The sign's five outlines, scaled into the box the dollar occupied."""
    sx0, sy0, sx1, sy1 = _bbox([p for contour in CONTOURS for p in contour])
    tx0, ty0, tx1, ty1 = target

    scale = (ty1 - ty0) / (sy1 - sy0)
    widest = (sx1 - sx0) * scale
    if widest > (tx1 - tx0) * WIDTH_LIMIT:
        scale = (tx1 - tx0) * WIDTH_LIMIT / (sx1 - sx0)

    # Centred on the dollar it replaces: same place, same weight on the page.
    cx = (tx0 + tx1) / 2 - (sx0 + sx1) / 2 * scale
    cy = (ty0 + ty1) / 2 - (sy0 + sy1) / 2 * scale
    return [
        [[round(x * scale + cx, 3), round(y * scale + cy, 3)] for x, y in contour]
        for contour in CONTOURS
    ]


def _shape_item(template, vertices, name):
    """One closed path, styled like the dollar it stands in for."""
    item = json.loads(json.dumps(template))
    item["nm"] = name
    item["ks"] = {
        "a": 0,
        "k": {
            "i": [[0, 0] for _ in vertices],
            "o": [[0, 0] for _ in vertices],
            "v": vertices,
            "c": True,
        },
        "ix": item.get("ks", {}).get("ix", 2),
    }
    return item


def _documents(doc):
    """The file's own layers, then the layers inside every precomposition."""
    for layer in doc.get("layers", []):
        yield layer
    for asset in doc.get("assets", []) or []:
        for layer in asset.get("layers", []) or []:
            yield layer


def _swap(path: str) -> int:
    with open(path, encoding="utf-8") as handle:
        doc = json.load(handle)

    wanted = TARGETS[os.path.basename(path)]
    swapped = 0
    for layer_name, group_name, shape_name in wanted:
        matched = False
        for layer in _documents(doc):
            if not str(layer.get("nm", "")).startswith(layer_name):
                continue
            for group in layer.get("shapes", []) or []:
                if group.get("nm") != group_name:
                    continue
                items = group.get("it", [])
                for index, item in enumerate(items):
                    if item.get("ty") != "sh" or item.get("nm") != shape_name:
                        continue
                    key = item.get("ks", {}).get("k", {})
                    if "v" not in key:
                        continue
                    outlines = _sign_shape(_bbox(key["v"]))
                    parts = [
                        _shape_item(
                            item,
                            vertices,
                            f"{shape_name} {number + 1}/{len(outlines)}",
                        )
                        for number, vertices in enumerate(outlines)
                    ]
                    # One shape in, five out: the group keeps its one fill, so
                    # the pieces read as a single letter.
                    items[index:index + 1] = parts
                    matched = True
                    swapped += 1
                    break
        if not matched:
            raise SystemExit(
                f"{os.path.basename(path)}: no {layer_name}/{group_name}/"
                f"{shape_name} - was the animation re-exported?"
            )

    if swapped == 0:
        raise SystemExit(f"{os.path.basename(path)}: nothing replaced")

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, separators=(",", ":"))
    print(f"{os.path.basename(path)}: {swapped} dollar(s) replaced")
    return swapped


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    folder = os.path.join(here, "..", "assets", "lottie")
    for name in TARGETS:
        _swap(os.path.join(folder, name))


if __name__ == "__main__":
    main()
