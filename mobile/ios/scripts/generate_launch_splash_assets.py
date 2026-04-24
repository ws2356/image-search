#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


IOS_ROOT = Path(__file__).resolve().parents[1]
ASSETS_ROOT = IOS_ROOT / "App/Assets.xcassets"

BACKGROUND_SET = ASSETS_ROOT / "LaunchSplashBackground.imageset"
CONTENT_SET = ASSETS_ROOT / "LaunchSplashContent.imageset"

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"


# ── colour helpers ─────────────────────────────────────────────────────────────

def _blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


# ── shield geometry ────────────────────────────────────────────────────────────

def _cubic_bezier_pts(
    p0: tuple[float, float], p1: tuple[float, float],
    p2: tuple[float, float], p3: tuple[float, float],
    n: int = 12,
) -> list[tuple[float, float]]:
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1.0 - t
        x = u**3*p0[0] + 3*u**2*t*p1[0] + 3*u*t**2*p2[0] + t**3*p3[0]
        y = u**3*p0[1] + 3*u**2*t*p1[1] + 3*u*t**2*p2[1] + t**3*p3[1]
        pts.append((x, y))
    return pts


def _quad_bezier_pts(
    p0: tuple[float, float], p1: tuple[float, float], p2: tuple[float, float],
    n: int = 10,
) -> list[tuple[float, float]]:
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1.0 - t
        x = u**2*p0[0] + 2*u*t*p1[0] + t**2*p2[0]
        y = u**2*p0[1] + 2*u*t*p1[1] + t**2*p2[1]
        pts.append((x, y))
    return pts


def _shield_polygon(
    origin_x: float, origin_y: float, unit: float, n: int = 12,
) -> list[tuple[int, int]]:
    """Approximate the shield SVG path as a pixel-space closed polygon.

    Shield path in 0–100 normalised coords:
        M50,6 C50,6 88,17 88,33 L88,63 Q88,84 50,97 Q12,84 12,63 L12,33 C12,17 50,6 50,6 Z
    """
    def p(nx: float, ny: float) -> tuple[float, float]:
        return (origin_x + nx * unit, origin_y + ny * unit)

    pts: list[tuple[float, float]] = []
    # Cubic (50,6) → (88,33) via CPs (50,6), (88,17)
    pts.extend(_cubic_bezier_pts(p(50, 6), p(50, 6), p(88, 17), p(88, 33), n))
    # Line (88,33) → (88,63)
    pts.append(p(88, 63))
    # Quad (88,63) → (50,97) via CP (88,84)  — skip first point, already added
    pts.extend(_quad_bezier_pts(p(88, 63), p(88, 84), p(50, 97), n)[1:])
    # Quad (50,97) → (12,63) via CP (12,84)  — skip first point
    pts.extend(_quad_bezier_pts(p(50, 97), p(12, 84), p(12, 63), n)[1:])
    # Line (12,63) → (12,33)
    pts.append(p(12, 33))
    # Cubic (12,33) → (50,6) via CPs (12,17), (50,6)  — skip first AND last
    # (last = start point; polygon closes automatically)
    pts.extend(_cubic_bezier_pts(p(12, 33), p(12, 17), p(50, 6), p(50, 6), n)[1:-1])

    return [(int(round(x)), int(round(y))) for x, y in pts]


# ── photo card ─────────────────────────────────────────────────────────────────

def _make_card_image(card_w: int, card_h: int, corner_r: int) -> Image.Image:
    """Landscape photo card: sky gradient + mountain silhouette + sun."""
    card = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card, "RGBA")

    # Sky gradient
    sky_top = (116, 186, 238)
    sky_bot = (198, 232, 250)
    for y in range(card_h):
        col = _blend(sky_top, sky_bot, y / max(1, card_h - 1))
        draw.line([(0, y), (card_w - 1, y)], fill=(*col, 255))

    # Mountain silhouette
    W, H = card_w, card_h
    mtn = [
        (0,          H),
        (W * 0.18,   H - H * 0.42),
        (W * 0.31,   H - H * 0.22),
        (W * 0.50,   H - H * 0.56),
        (W * 0.65,   H - H * 0.33),
        (W * 0.80,   H - H * 0.18),
        (W,          H),
    ]
    draw.polygon([(int(x), int(y)) for x, y in mtn], fill=(37, 74, 136, 255))

    # Sun
    sx, sy = int(W * 0.81), int(H * 0.22)
    sr = max(2, int(W * 0.065))
    draw.ellipse((sx - sr, sy - sr, sx + sr, sy + sr), fill=(255, 184, 0, 230))

    # Rounded-rect alpha mask
    mask = Image.new("L", (card_w, card_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, card_w - 1, card_h - 1), radius=corner_r, fill=255,
    )
    card.putalpha(mask)

    # Subtle white border overlay
    border = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    ImageDraw.Draw(border, "RGBA").rounded_rectangle(
        (0, 0, card_w - 1, card_h - 1), radius=corner_r,
        outline=(255, 255, 255, 110), width=max(1, card_w // 60),
    )
    card.alpha_composite(border)
    return card


# ── rotation helper ────────────────────────────────────────────────────────────

def _paste_rotated(
    canvas: Image.Image, layer: Image.Image,
    center: tuple[int, int], angle_deg: float,
) -> None:
    """Rotate *layer* by *angle_deg* and composite it centred at *center* on *canvas*."""
    rotated = (
        layer.rotate(-angle_deg, expand=True, resample=Image.BICUBIC)
        if abs(angle_deg) > 0.01 else layer
    )
    rx, ry = rotated.size
    cx, cy = center
    dest_x = cx - rx // 2
    dest_y = cy - ry // 2

    cw, ch = canvas.size
    src_x1, src_y1 = max(0, -dest_x), max(0, -dest_y)
    src_x2, src_y2 = min(rx, cw - dest_x), min(ry, ch - dest_y)
    if src_x2 <= src_x1 or src_y2 <= src_y1:
        return

    cropped = rotated.crop((src_x1, src_y1, src_x2, src_y2))
    canvas.paste(cropped, (max(0, dest_x), max(0, dest_y)), cropped.split()[3])


# ── shield art ─────────────────────────────────────────────────────────────────

def _draw_shield_art(
    image: Image.Image,
    *,
    shield_cx: float,
    shield_cy: float,
    unit: float,
    shield_fill_top: tuple[int, int, int],
    shield_fill_bottom: tuple[int, int, int],
    shield_border_alpha: int = 100,
    shadow_alpha: int = 150,
) -> None:
    """Draw shield + stacked photo cards onto *image* (RGBA, in-place)."""
    w, h = image.size
    # Visual centre of shield in 0–100 space: x=50, y=51.5
    origin_x = shield_cx - 50.0 * unit
    origin_y = shield_cy - 51.5 * unit

    poly = _shield_polygon(origin_x, origin_y, unit)
    ys = [pt[1] for pt in poly]
    y_min, y_max = min(ys), max(ys)

    # ── drop shadow ───────────────────────────────────────────────────────────
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(poly, fill=(0, 30, 90, shadow_alpha))
    blur_r = max(2, int(unit * 2.5))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=blur_r))
    shadow = ImageChops.offset(shadow, 0, max(1, int(unit * 1.5)))
    image.alpha_composite(shadow)

    # ── shield gradient fill ──────────────────────────────────────────────────
    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad, "RGBA")
    for y in range(max(0, y_min - 1), min(h, y_max + 2)):
        t = (y - y_min) / max(1, y_max - y_min)
        col = _blend(shield_fill_top, shield_fill_bottom, t)
        gd.line([(0, y), (w - 1, y)], fill=(*col, 255))
    shield_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shield_mask).polygon(poly, fill=255)
    grad.putalpha(shield_mask)
    image.alpha_composite(grad)

    # ── photo stack (clipped to shield) ───────────────────────────────────────
    card_l, card_t = 25.0, 28.0
    card_w_n, card_h_n, corner_n = 50.0, 35.0, 3.0
    card_w_px = max(4, int(card_w_n * unit))
    card_h_px = max(3, int(card_h_n * unit))
    corner_px = max(1, int(corner_n * unit))
    card_cx = int(origin_x + (card_l + card_w_n / 2.0) * unit)
    card_cy = int(origin_y + (card_t + card_h_n / 2.0) * unit)

    card_img = _make_card_image(card_w_px, card_h_px, corner_px)
    cards = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for angle in (-9.0, -4.0, 0.0):
        _paste_rotated(cards, card_img, (card_cx, card_cy), angle)

    # Clip card stack to shield shape
    cr, cg, cb, ca = cards.split()
    clipped_a = Image.composite(ca, Image.new("L", (w, h), 0), shield_mask)
    image.alpha_composite(Image.merge("RGBA", (cr, cg, cb, clipped_a)))

    # ── shield rim highlight ───────────────────────────────────────────────────
    rim = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(rim).polygon(
        poly,
        outline=(255, 255, 255, shield_border_alpha),
        width=max(1, int(unit * 0.5)),
    )
    image.alpha_composite(rim)


# ── public drawing functions ───────────────────────────────────────────────────

def _draw_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size, "white")
    draw = ImageDraw.Draw(image, "RGBA")

    top_color = (240, 246, 255)
    mid_color  = (255, 255, 255)
    bot_color  = (243, 253, 246)
    for y in range(height):
        ratio = y / (height - 1)
        if ratio < 0.5:
            col = _blend(top_color, mid_color, ratio / 0.5)
        else:
            col = _blend(mid_color, bot_color, (ratio - 0.5) / 0.5)
        draw.line([(0, y), (width, y)], fill=col)

    cs = int(width * 0.60)
    off = int(width * 0.18)
    draw.ellipse((width - cs + off, -off, width + off, cs - off), fill=(0, 122, 255, 15))
    draw.ellipse((-off, height - cs + off, cs - off, height + off), fill=(48, 209, 88, 15))

    return image


def _draw_content(scale: int) -> Image.Image:
    width = 300 * scale
    height = 360 * scale
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")

    icon_size = 120 * scale
    icon_x = (width - icon_size) // 2
    icon_y = 0

    # ── icon visual ───────────────────────────────────────────────────────────
    blue_top    = (0, 122, 255)
    blue_bottom = (0, 85, 212)
    icon_layer = Image.new("RGBA", (icon_size, icon_size), (0, 0, 0, 0))
    id_ = ImageDraw.Draw(icon_layer, "RGBA")
    for y in range(icon_size):
        col = _blend(blue_top, blue_bottom, y / (icon_size - 1))
        id_.line([(0, y), (icon_size - 1, y)], fill=(*col, 255))

    # Shield + stacked photo cards
    _draw_shield_art(
        icon_layer,
        shield_cx=icon_size / 2.0,
        shield_cy=icon_size / 2.0,
        unit=icon_size / 100.0 * 0.88,
        shield_fill_top=(255, 255, 255),
        shield_fill_bottom=(206, 227, 255),
        shield_border_alpha=105,
        shadow_alpha=130,
    )

    # Top-half shine
    shine = Image.new("RGBA", (icon_size, icon_size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine, "RGBA")
    half = icon_size // 2
    for y in range(half):
        alpha = int(50 * (1.0 - y / half))
        sd.line([(0, y), (icon_size - 1, y)], fill=(255, 255, 255, alpha))
    icon_layer.alpha_composite(shine)

    # iOS rounded-rect clip — applied last so shadow stays inside the icon square
    ios_mask = Image.new("L", (icon_size, icon_size), 0)
    ImageDraw.Draw(ios_mask).rounded_rectangle(
        (0, 0, icon_size - 1, icon_size - 1), radius=28 * scale, fill=255,
    )
    ir, ig, ib, ia = icon_layer.split()
    ia = Image.composite(ia, Image.new("L", (icon_size, icon_size), 0), ios_mask)
    icon_layer = Image.merge("RGBA", (ir, ig, ib, ia))

    image.paste(icon_layer, (icon_x, icon_y), icon_layer.split()[3])

    # ── title & subtitle ──────────────────────────────────────────────────────
    title_font    = ImageFont.truetype(FONT_BOLD, 28 * scale)
    subtitle_font = ImageFont.truetype(FONT_REGULAR, 14 * scale)

    title    = "AuBackup"
    subtitle = "Back up & search your photos, locally"

    title_y = icon_y + icon_size + 24 * scale
    tb = draw.textbbox((0, 0), title, font=title_font)
    draw.text(
        ((width - (tb[2] - tb[0])) // 2, title_y),
        title, font=title_font, fill=(28, 28, 30, 255),
    )

    subtitle_y = title_y + 42 * scale
    sb = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    draw.text(
        ((width - (sb[2] - sb[0])) // 2, subtitle_y),
        subtitle, font=subtitle_font, fill=(110, 110, 115, 255),
    )

    # ── pills ─────────────────────────────────────────────────────────────────
    pill_font = ImageFont.truetype(FONT_BOLD, 12 * scale)
    pills = [
        ("Secure", (232, 244, 255, 255), (0, 122, 255, 255)),
        ("Local",  (232, 255, 240, 255), (37, 168, 75, 255)),
        ("Fast",   (245, 240, 255, 255), (88, 86, 214, 255)),
    ]

    pill_padding_x = 12 * scale
    pill_height    = 26 * scale
    pill_gap       = 8 * scale

    pill_widths: list[int] = []
    for text, _, _ in pills:
        pb = draw.textbbox((0, 0), text, font=pill_font)
        pill_widths.append((pb[2] - pb[0]) + pill_padding_x * 2)

    total_width = sum(pill_widths) + pill_gap * (len(pills) - 1)
    current_x = (width - total_width) // 2
    pill_y = subtitle_y + 36 * scale

    for i, (text, bg_color, text_color) in enumerate(pills):
        pw = pill_widths[i]
        draw.rounded_rectangle(
            (current_x, pill_y, current_x + pw, pill_y + pill_height),
            radius=pill_height // 2,
            fill=bg_color,
        )
        pb = draw.textbbox((0, 0), text, font=pill_font)
        tw, th = pb[2] - pb[0], pb[3] - pb[1]
        draw.text(
            (current_x + (pw - tw) // 2, pill_y + (pill_height - th) // 2 - scale // 2),
            text, font=pill_font, fill=text_color,
        )
        current_x += pw + pill_gap

    return image


def _write_contents_json(asset_dir: Path, *, base_name: str) -> None:
    content = (
        "{\n"
        "  \"images\" : [\n"
        f"    {{ \"filename\" : \"{base_name}.png\", \"idiom\" : \"universal\", \"scale\" : \"1x\" }},\n"
        f"    {{ \"filename\" : \"{base_name}@2x.png\", \"idiom\" : \"universal\", \"scale\" : \"2x\" }},\n"
        f"    {{ \"filename\" : \"{base_name}@3x.png\", \"idiom\" : \"universal\", \"scale\" : \"3x\" }}\n"
        "  ],\n"
        "  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n"
        "}\n"
    )
    (asset_dir / "Contents.json").write_text(content, encoding="utf-8")


def main() -> None:
    BACKGROUND_SET.mkdir(parents=True, exist_ok=True)
    CONTENT_SET.mkdir(parents=True, exist_ok=True)

    _write_contents_json(BACKGROUND_SET, base_name="LaunchSplashBackground")
    _write_contents_json(CONTENT_SET, base_name="LaunchSplashContent")

    for scale, size, suffix in (
        (1, (390, 844), ""),
        (2, (780, 1688), "@2x"),
        (3, (1170, 2532), "@3x"),
    ):
        _draw_background(size).save(BACKGROUND_SET / f"LaunchSplashBackground{suffix}.png")
        _draw_content(scale).save(CONTENT_SET / f"LaunchSplashContent{suffix}.png")


if __name__ == "__main__":
    main()
