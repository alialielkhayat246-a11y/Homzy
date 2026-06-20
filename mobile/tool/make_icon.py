"""Generate the Homzy launcher icon (the house-with-window mark) as PNGs.

Mirrors the in-app logo (frontend/mobile HouseLogo): a house outline with a
2x2 blue window grid. Outputs:
  assets/icon/homzy_icon.png     navy bg + white house  (legacy / iOS)
  assets/icon/homzy_icon_fg.png  transparent + white house, smaller (adaptive
                                 foreground; background colour set in pubspec)
"""
from pathlib import Path

from PIL import Image, ImageDraw

NAVY = (13, 27, 42, 255)      # #0D1B2A
BLUE = (37, 99, 235, 255)     # #2563EB
WHITE = (255, 255, 255, 255)

SIZE = 1024

# House mark in a 64-unit design space (same as the SVG/CustomPaint).
ROOF = [(10, 56), (10, 28), (32, 10), (54, 28), (54, 56)]
WINDOWS = [(24, 34), (33, 34), (24, 43), (33, 43)]
WIN = 7
STROKE64 = 6


def _draw_house(draw: ImageDraw.ImageDraw, scale: float, ox: float, oy: float):
    def m(x, y):
        return (ox + x * scale, oy + y * scale)

    width = int(STROKE64 * scale)
    pts = [m(x, y) for x, y in ROOF]
    draw.line(pts, fill=WHITE, width=width, joint="curve")
    # round the line caps + corners
    r = width / 2
    for px, py in pts:
        draw.ellipse([px - r, py - r, px + r, py + r], fill=WHITE)
    # windows
    rad = max(2, int(1.5 * scale))
    for wx, wy in WINDOWS:
        x0, y0 = m(wx, wy)
        x1, y1 = m(wx + WIN, wy + WIN)
        draw.rounded_rectangle([x0, y0, x1, y1], radius=rad, fill=BLUE)


def _render(bg, house_height_units_frac):
    img = Image.new("RGBA", (SIZE, SIZE), bg)
    draw = ImageDraw.Draw(img)
    # house spans x:10..54 (44 wide), y:10..56 (46 tall)
    target_h = SIZE * house_height_units_frac
    scale = target_h / 46.0
    house_w = 44 * scale
    ox = (SIZE - house_w) / 2 - 10 * scale
    oy = (SIZE - target_h) / 2 - 10 * scale
    _draw_house(draw, scale, ox, oy)
    return img


def main():
    out = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    # Full icon: navy background, house at ~55% height.
    _render(NAVY, 0.55).save(out / "homzy_icon.png")
    # Adaptive foreground: transparent, smaller (~42%) to stay in the safe zone.
    _render((0, 0, 0, 0), 0.42).save(out / "homzy_icon_fg.png")
    print("wrote", out / "homzy_icon.png", "and", out / "homzy_icon_fg.png")


if __name__ == "__main__":
    main()
