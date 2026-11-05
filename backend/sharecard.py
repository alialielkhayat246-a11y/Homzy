"""Branded share card for a marketplace unit (Facebook / WhatsApp / Instagram).

Renders the unit's cover photo with a Homzy overlay: purpose badge, title,
key facts and the price. Used as the og:image of /listing/{id} (1200x630,
small enough for WhatsApp previews) and as a downloadable square post
(1080x1080) for Instagram.
"""
from __future__ import annotations

import io
import unicodedata
from pathlib import Path

import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFont

FONTS = Path(__file__).parent / "fonts"
NAVY = (11, 29, 54)
TEAL = (13, 148, 136)
WHITE = (255, 255, 255)
SOFT = (215, 226, 236)


def _font(size: int, heavy: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / ("Cairo-800.ttf" if heavy else "Cairo-700.ttf")), size)


_CMAP: set[int] | None = None


def _cmap() -> set[int]:
    global _CMAP
    if _CMAP is None:
        from fontTools.ttLib import TTFont
        _CMAP = set(TTFont(str(FONTS / "Cairo-700.ttf")).getBestCmap())
    return _CMAP


def _shape(s: str) -> str:
    """Pillow here has no complex-script layout, so join + reorder Arabic ourselves.
    Cairo lacks a few isolated presentation forms (ا ر و ف م …): fall those back to
    the base letter, which the font draws in its isolated shape anyway."""
    cm = _cmap()
    shaped = "".join(c if ord(c) in cm or c.isspace() else (unicodedata.normalize("NFKC", c) or c)
                     for c in arabic_reshaper.reshape(s))
    return get_display(shaped)


def _width(draw: ImageDraw.ImageDraw, s: str, font) -> int:
    return int(draw.textlength(_shape(s), font=font))


def _wrap(draw, text: str, font, max_w: int, max_lines: int) -> list[str]:
    words, lines, cur = text.split(), [], ""
    for w in words:
        nxt = (cur + " " + w).strip()
        if _width(draw, nxt, font) <= max_w or not cur:
            cur = nxt
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        while lines[-1] and _width(draw, lines[-1] + "…", font) > max_w:
            lines[-1] = lines[-1].rsplit(" ", 1)[0] if " " in lines[-1] else lines[-1][:-1]
        lines[-1] += "…"
    return lines


def _cover(img: Image.Image, w: int, h: int) -> Image.Image:
    s = max(w / img.width, h / img.height)
    img = img.resize((max(w, round(img.width * s)), max(h, round(img.height * s))), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def _money(n) -> str:
    try:
        return f"{int(float(n)):,} ج.م"
    except (TypeError, ValueError):
        return ""


def render(listing: dict, photo: bytes | None, square: bool = False, company: str = "") -> bytes:
    W, H = (1080, 1080) if square else (1200, 630)
    M = 56 if square else 48
    if photo:
        base = _cover(Image.open(io.BytesIO(photo)).convert("RGB"), W, H)
    else:
        base = Image.new("RGB", (W, H), NAVY)

    # darken the lower part so the text always reads, whatever the photo
    shade = Image.new("RGB", (W, H), NAVY)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    top = int(H * (0.42 if square else 0.30))
    for y in range(top, H):
        md.line([(0, y), (W, y)], fill=int(235 * ((y - top) / (H - top)) ** 1.1))
    md.rectangle([0, 0, W, 6], fill=0)
    base = Image.composite(shade, base, mask)
    d = ImageDraw.Draw(base)

    # brand chip (top-left) + purpose badge (top-right)
    bf = _font(30 if square else 28, heavy=True)
    brand = "Homzy"
    bw = int(d.textlength(brand, font=bf))
    d.rounded_rectangle([M, M, M + bw + 74, M + 56], radius=16, fill=WHITE)
    hx, hy = M + 16, M + 13  # little house mark
    d.polygon([(hx, hy + 13), (hx + 16, hy), (hx + 32, hy + 13)], fill=NAVY)
    d.rectangle([hx + 4, hy + 13, hx + 28, hy + 31], fill=NAVY)
    d.rectangle([hx + 13, hy + 19, hx + 19, hy + 31], fill=TEAL)
    d.text((M + 58, M + 28), brand, font=bf, fill=NAVY, anchor="lm")

    purpose = "للإيجار" if listing.get("purpose") == "rent" else "للبيع"
    pf = _font(30 if square else 28, heavy=True)
    pw = _width(d, purpose, pf)
    d.rounded_rectangle([W - M - pw - 44, M, W - M, M + 56], radius=28, fill=TEAL)
    d.text((W - M - 22, M + 27), _shape(purpose), font=pf, fill=WHITE, anchor="rm")

    # bottom block, right-aligned (RTL): title, facts, then the price pill on the left
    tf = _font(58 if square else 50, heavy=True)
    ff = _font(32 if square else 28)
    title_lines = _wrap(d, (listing.get("title") or "").strip() or "عقار", tf, W - 2 * M, 3 if square else 2)

    facts = []
    if listing.get("bedrooms"):
        facts.append(f"{listing['bedrooms']} غرف")
    if listing.get("bathrooms"):
        facts.append(f"{listing['bathrooms']} حمام")
    if listing.get("size_sqm"):
        facts.append(f"{int(float(listing['size_sqm']))} م²")
    if listing.get("area"):
        facts.append(str(listing["area"]))
    facts_txt = "  •  ".join(facts)

    price = _money(listing.get("price"))
    if price and listing.get("purpose") == "rent":
        price += " / شهر"
    prf = _font(46 if square else 40, heavy=True)
    pill_h = 76 if square else 68

    y = H - M - pill_h
    if price:
        prw = _width(d, price, prf)
        d.rounded_rectangle([M, y, M + prw + 52, y + pill_h], radius=pill_h // 2, fill=TEAL)
        d.text((M + 26 + prw / 2, y + pill_h / 2), _shape(price), font=prf, fill=WHITE, anchor="mm")
    if company:
        cf = _font(26 if square else 24)
        d.text((W - M, y + pill_h / 2), _shape("عن طريق " + company), font=cf, fill=SOFT, anchor="rm")

    y -= 22
    if facts_txt:
        lh = int(ff.size * 1.45)
        y -= lh
        d.text((W - M, y + lh / 2), _shape(facts_txt), font=ff, fill=SOFT, anchor="rm")
    lh = int(tf.size * 1.32)
    for line in reversed(title_lines):
        y -= lh
        d.text((W - M, y + lh / 2), _shape(line), font=tf, fill=WHITE, anchor="rm")

    out = io.BytesIO()
    base.save(out, "JPEG", quality=82, optimize=True, progressive=True)
    return out.getvalue()
