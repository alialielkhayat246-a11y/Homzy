"""Generate Homzy favicon/app-icon assets from the brand mark (navy rounded
square + white house outline + teal window). Run:  python tools/make_icons.py

Outputs into frontend/assets/ :  icon.svg, favicon.ico, favicon-48.png,
icon-192.png, icon-512.png, apple-touch-icon.png (180).
Real files at stable URLs are required for Google to show the site's favicon in
search results (a data: URI is not used by Google).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

NAVY = (11, 29, 54, 255)     # #0B1D36
WHITE = (255, 255, 255, 255)
TEAL = (11, 85, 99, 255)     # #0B5563

OUT = Path(__file__).resolve().parents[1] / "frontend" / "assets"
OUT.mkdir(parents=True, exist_ok=True)

# Geometry on a 64-unit grid (matches the inline SVG used across the site).
HOUSE = [(16, 50), (16, 30), (32, 17), (48, 30), (48, 50)]
WIN = (27, 34, 37, 44)       # x0,y0,x1,y1
STROKE = 4.6


def render(size: int) -> Image.Image:
    """Draw the mark at `size` px, supersampled 4x for clean edges."""
    ss = 4
    S = size * ss
    k = S / 64.0
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # navy rounded-square background
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=14 * k, fill=NAVY)
    # white house outline (round joints via a circle at each vertex)
    w = STROKE * k
    pts = [(x * k, y * k) for x, y in HOUSE]
    d.line(pts, fill=WHITE, width=int(round(w)), joint="curve")
    r = w / 2.0
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)
    # teal window
    x0, y0, x1, y1 = (v * k for v in WIN)
    d.rounded_rectangle([x0, y0, x1, y1], radius=2 * k, fill=TEAL)
    return img.resize((size, size), Image.LANCZOS)


SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>"
    "<rect width='64' height='64' rx='14' fill='#0B1D36'/>"
    "<path d='M16 50V30L32 17l16 13v20' stroke='#fff' stroke-width='4.6' "
    "fill='none' stroke-linejoin='round' stroke-linecap='round'/>"
    "<rect x='27' y='34' width='10' height='10' rx='2' fill='#0B5563'/></svg>\n"
)


def main() -> None:
    (OUT / "icon.svg").write_text(SVG, encoding="utf-8")
    render(512).save(OUT / "icon-512.png")
    render(192).save(OUT / "icon-192.png")
    render(180).save(OUT / "apple-touch-icon.png")
    render(48).save(OUT / "favicon-48.png")
    # multi-size .ico for legacy + Google
    ico = render(256)
    ico.save(OUT / "favicon.ico",
             sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote:", *(p.name for p in sorted(OUT.glob("icon*"))),
          "favicon.ico favicon-48.png apple-touch-icon.png")


if __name__ == "__main__":
    main()
