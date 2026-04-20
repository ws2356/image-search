#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[1]
ASSETS_ROOT = REPO_ROOT / "mobile/ios/App/Assets.xcassets"

BACKGROUND_SET = ASSETS_ROOT / "LaunchSplashBackground.imageset"
CONTENT_SET = ASSETS_ROOT / "LaunchSplashContent.imageset"

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"


def _blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _draw_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size, "white")
    draw = ImageDraw.Draw(image, "RGBA")

    top_color = (242, 248, 255)
    middle_color = (255, 255, 255)
    bottom_color = (245, 255, 248)
    for y in range(height):
        ratio = y / (height - 1)
        if ratio < 0.5:
            color = _blend(top_color, middle_color, ratio / 0.5)
        else:
            color = _blend(middle_color, bottom_color, (ratio - 0.5) / 0.5)
        draw.line([(0, y), (width, y)], fill=color)

    circle_size = int(width * 0.62)
    offset = int(width * 0.2)
    draw.ellipse(
        (width - circle_size + offset, -offset, width + offset, circle_size - offset),
        fill=(0, 122, 255, 18),
    )
    draw.ellipse(
        (-offset, height - circle_size + offset, circle_size - offset, height + offset),
        fill=(48, 209, 88, 18),
    )

    return image


def _draw_logo_symbol(
    draw: ImageDraw.ImageDraw,
    *,
    origin_x: float,
    origin_y: float,
    symbol_size: float,
) -> None:
    scale = symbol_size / 66.0

    def sx(value: float) -> int:
        return int(origin_x + value * scale)

    def sy(value: float) -> int:
        return int(origin_y + value * scale)

    def rounded_rect(x0: float, y0: float, x1: float, y1: float, radius: float, fill: tuple[int, int, int, int]) -> None:
        draw.rounded_rectangle((sx(x0), sy(y0), sx(x1), sy(y1)), radius=max(1, int(radius * scale)), fill=fill)

    # Photo stack (approximation of the SVG in m08-splash-screens updated.html)
    rounded_rect(6.5, 21.5, 40.5, 49.5, 5.0, (255, 255, 255, 70))
    rounded_rect(11.0, 16.5, 45.0, 44.5, 5.0, (255, 255, 255, 96))
    rounded_rect(16.0, 11.5, 50.0, 39.5, 5.0, (255, 255, 255, 255))
    rounded_rect(18.0, 13.5, 48.0, 37.5, 3.0, (0, 100, 220, 30))

    mountain = [
        (20.0, 34.0),
        (27.0, 23.0),
        (33.0, 30.0),
        (37.0, 26.0),
        (50.0, 34.0),
    ]
    draw.polygon([(sx(x), sy(y)) for x, y in mountain], fill=(0, 100, 220, 96))

    draw.ellipse((sx(41.0), sy(14.0), sx(47.0), sy(20.0)), fill=(255, 180, 0, 210))

    # Transfer arrow
    arrow_width = max(2, int(2.5 * scale))
    support_width = max(1, int(1.5 * scale))
    draw.line([(sx(54.0), sy(28.0)), (sx(62.0), sy(33.0)), (sx(54.0), sy(38.0))], fill=(255, 255, 255, 210), width=arrow_width)
    draw.line([(sx(44.0), sy(33.0)), (sx(61.0), sy(33.0))], fill=(255, 255, 255, 150), width=support_width)


def _draw_content(scale: int) -> Image.Image:
    width = 300 * scale
    height = 360 * scale
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")

    icon_size = 120 * scale
    icon_x = (width - icon_size) // 2
    icon_y = 0

    blue_top = (0, 122, 255)
    blue_bottom = (0, 85, 212)
    icon_layer = Image.new("RGBA", (icon_size, icon_size), (0, 0, 0, 0))
    icon_draw = ImageDraw.Draw(icon_layer, "RGBA")
    for y in range(icon_size):
        color = _blend(blue_top, blue_bottom, y / (icon_size - 1))
        icon_draw.line([(0, y), (icon_size, y)], fill=(*color, 255))

    mask = Image.new("L", (icon_size, icon_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, icon_size, icon_size), radius=28 * scale, fill=255)
    image.paste(icon_layer, (icon_x, icon_y), mask)

    _draw_logo_symbol(
        draw,
        origin_x=icon_x + 27 * scale,
        origin_y=icon_y + 27 * scale,
        symbol_size=66 * scale,
    )

    title_font = ImageFont.truetype(FONT_BOLD, 28 * scale)
    subtitle_font = ImageFont.truetype(FONT_REGULAR, 14 * scale)

    title = "Album Transporter"
    subtitle = "Your photos, backed up to your PC"

    title_y = icon_y + icon_size + 24 * scale
    title_box = draw.textbbox((0, 0), title, font=title_font)
    title_w = title_box[2] - title_box[0]
    draw.text((width // 2 - title_w // 2, title_y), title, font=title_font, fill=(28, 28, 30, 255))

    subtitle_y = title_y + 42 * scale
    subtitle_box = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    subtitle_w = subtitle_box[2] - subtitle_box[0]
    draw.text((width // 2 - subtitle_w // 2, subtitle_y), subtitle, font=subtitle_font, fill=(110, 110, 115, 255))

    pill_font = ImageFont.truetype(FONT_BOLD, 12 * scale)
    pills = [
        ("Secure", (232, 244, 255, 255), (0, 122, 255, 255)),
        ("Local", (232, 255, 240, 255), (37, 168, 75, 255)),
        ("Fast", (245, 240, 255, 255), (88, 86, 214, 255)),
    ]

    pill_padding_x = 12 * scale
    pill_height = 26 * scale
    pill_gap = 8 * scale

    pill_widths: list[int] = []
    for text, _, _ in pills:
        text_box = draw.textbbox((0, 0), text, font=pill_font)
        pill_widths.append((text_box[2] - text_box[0]) + pill_padding_x * 2)

    total_width = sum(pill_widths) + pill_gap * (len(pills) - 1)
    current_x = width // 2 - total_width // 2
    pill_y = subtitle_y + 36 * scale

    for index, (text, bg_color, text_color) in enumerate(pills):
        pill_width = pill_widths[index]
        draw.rounded_rectangle(
            (current_x, pill_y, current_x + pill_width, pill_y + pill_height),
            radius=pill_height // 2,
            fill=bg_color,
        )
        text_box = draw.textbbox((0, 0), text, font=pill_font)
        text_w = text_box[2] - text_box[0]
        text_h = text_box[3] - text_box[1]
        draw.text(
            (current_x + (pill_width - text_w) // 2, pill_y + (pill_height - text_h) // 2 - scale // 2),
            text,
            font=pill_font,
            fill=text_color,
        )
        current_x += pill_width + pill_gap

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
