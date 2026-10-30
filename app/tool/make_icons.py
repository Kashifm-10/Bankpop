"""Renders the action icons from `design/app-icons.html` into assets.

The drawings live as SVG in the design file so they can be edited side by side;
the app ships them as PNG, because that is what `Image.asset` wants and what the
icon-set buttons are measured against. This is the step in between: every
`<svg class="icon" data-name="...">` is rendered on a transparent sheet with
headless Chrome, trimmed to the ink, squared off and written to
`assets/Icons/<name>.png`.

Run it from the `app` directory, with Chrome installed:

    python tool/make_icons.py            # every icon, or
    python tool/make_icons.py advance    # just the ones named

Rendering needs Google Chrome; the trim/save half needs Pillow.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile

from PIL import Image

SIDE = 512          # render size, in pixels
MARGIN = 0.045      # breathing room kept around the ink, as a fraction of the side

CHROME_CANDIDATES = (
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
    "chromium",
)


def _chrome() -> str:
    for path in CHROME_CANDIDATES:
        if os.path.sep in path:
            if os.path.exists(path):
                return path
        else:
            from shutil import which
            found = which(path)
            if found:
                return found
    raise SystemExit("Chrome not found - install it, or render the icons by hand.")


def _icons(html: str) -> dict[str, str]:
    """Every icon in the design file, keyed by its `data-name`."""
    pattern = re.compile(
        r'<svg class="icon"[^>]*data-name="([^"]+)".*?</svg>', re.S
    )
    return {m.group(1): m.group(0) for m in pattern.finditer(html)}


def _defs(html: str) -> str:
    """The shared drawings - the money mark, above all - that the icons `<use>`.

    In the design page they live once, in a hidden sheet at the top; each icon
    is rendered on a page of its own here, so the sheet has to come along or an
    icon that shows money is drawn with a blank coin.
    """
    match = re.search(r'<svg width="0" height="0".*?</svg>', html, re.S)
    return match.group(0) if match else ""


def _render(chrome: str, svg: str, defs: str, out: str) -> None:
    page = os.path.join(tempfile.mkdtemp(prefix="bankpop-icon-"), "icon.html")
    with open(page, "w", encoding="utf-8") as handle:
        # The drawing fills the sheet: no padding, no page margin, and a fully
        # transparent background, so the trim below sees only the icon itself.
        handle.write(
            "<!DOCTYPE html><html><head><meta charset='utf-8'><style>"
            "html,body{margin:0;padding:0;background:transparent;}"
            f"svg{{display:block;width:{SIDE}px;height:{SIDE}px;}}"
            "</style></head><body>"
            + defs
            + svg.replace('class="icon"', 'class="icon on"')
            + "</body></html>"
        )
    subprocess.run(
        [
            chrome,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--default-background-color=00000000",
            f"--screenshot={out}",
            f"--window-size={SIDE},{SIDE}",
            f"file:///{page.replace(os.sep, '/')}",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _trim(path: str) -> None:
    """Cut the transparent border off, then square the picture and give the
    ink the same margin on every side, so no icon sits lopsided in its tile."""
    image = Image.open(path).convert("RGBA")
    box = image.getbbox()
    if box is None:
        raise SystemExit(f"{path}: nothing was drawn")
    ink = image.crop(box)
    side = max(ink.size)
    pad = int(side * MARGIN)
    canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    canvas.paste(
        ink,
        ((canvas.width - ink.width) // 2, (canvas.height - ink.height) // 2),
        ink,
    )
    canvas.save(path)


def main(argv: list[str]) -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    design = os.path.join(here, "..", "..", "design", "app-icons.html")
    out_dir = os.path.join(here, "..", "assets", "Icons")
    with open(design, encoding="utf-8") as handle:
        html = handle.read()
    icons = _icons(html)
    defs = _defs(html)

    wanted = [name for name in argv if not name.startswith("-")] or sorted(icons)
    chrome = _chrome()
    for name in wanted:
        if name not in icons:
            raise SystemExit(f"no icon named {name!r} in {design}")
        target = os.path.abspath(os.path.join(out_dir, f"{name}.png"))
        _render(chrome, icons[name], defs, target)
        _trim(target)
        with Image.open(target) as done:
            print(f"{name}: {done.size[0]}x{done.size[1]}")


if __name__ == "__main__":
    main(sys.argv[1:])
