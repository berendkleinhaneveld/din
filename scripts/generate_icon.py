#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "pillow>=12.1.0",
# ]
# ///
"""Generate the 1024x1024 Din app icon PNG.

Outputs: scripts/build/icon_1024.png
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
MARGIN = 100
CORNER = 185

OUT_DIR = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(OUT_DIR, exist_ok=True)


def rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.pieslice([x0, y0, x0 + 2 * radius, y0 + 2 * radius], 180, 270, fill=fill)
    draw.pieslice([x1 - 2 * radius, y0, x1, y0 + 2 * radius], 270, 360, fill=fill)
    draw.pieslice([x0, y1 - 2 * radius, x0 + 2 * radius, y1], 90, 180, fill=fill)
    draw.pieslice([x1 - 2 * radius, y1 - 2 * radius, x1, y1], 0, 90, fill=fill)


def wave_y(x, base_y, amplitude, freq, phase):
    """Compute a sine-wave Y value at position x."""
    return base_y + amplitude * math.sin(freq * x + phase)


def draw_glass_wave(img, y_func, edge_color, body_color, bloom_depth, bloom_blur):
    """Draw a glass-like wave with a bright edge that blooms downward.

    - edge_color: bright RGBA for the thin top edge
    - body_color: RGB base for the gradient fill below the edge
    - bloom_depth: how many pixels the bloom/gradient extends downward
    - bloom_blur: gaussian blur radius for the edge bloom
    """
    # 1) Gradient body — per-column vertical gradient from wave crest downward.
    #    Brightest just below the edge, fading to transparent.
    body_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body_pixels = body_layer.load()
    br, bg, bb = body_color
    for x in range(SIZE):
        wy = int(y_func(x))
        for dy in range(bloom_depth):
            y = wy + dy
            if y < 0 or y >= SIZE:
                continue
            # Exponential falloff — fast fade for glass look
            t = dy / bloom_depth
            alpha = int(edge_color[3] * 0.6 * math.exp(-3.5 * t))
            if alpha < 1:
                break
            body_pixels[x, y] = (br, bg, bb, alpha)

    img = Image.alpha_composite(img, body_layer)

    # 2) Bright thin edge — drawn as a 1px line then softly blurred for bloom
    edge_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(edge_layer)
    points = [(x, int(y_func(x))) for x in range(SIZE)]
    draw.line(points, fill=edge_color, width=1)

    # Bloom: blur a copy of the edge and composite it underneath the sharp edge
    bloom_layer = edge_layer.copy()
    bloom_layer = bloom_layer.filter(ImageFilter.GaussianBlur(radius=bloom_blur))
    img = Image.alpha_composite(img, bloom_layer)
    img = Image.alpha_composite(img, edge_layer)

    return img


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Rounded-rect mask
    mask = Image.new("L", (SIZE, SIZE), 0)
    rounded_rect(
        ImageDraw.Draw(mask),
        (MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN),
        CORNER,
        255,
    )

    # Dark background
    content = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for y in range(SIZE):
        t = y / SIZE
        r = int(5 + t * 8)
        g = int(5 + t * 8)
        b = int(12 + t * 18)
        for x in range(SIZE):
            content.putpixel((x, y), (r, g, b, 255))

    # Wave definitions — back to front
    # edge_color: bright thin line RGBA
    # body_color: RGB tint for the downward gradient
    # bloom_depth: px the gradient extends below the edge
    # bloom_blur: blur radius for the edge bloom halo
    waves = [
        {
            "base_y": 300,
            "amplitude": 25,
            "freq": 0.006,
            "phase": 0.8,
            "edge": (100, 190, 235, 140),
            "body": (25, 60, 100),
            "depth": 200,
            "blur": 10,
        },
        {
            "base_y": 400,
            "amplitude": 45,
            "freq": 0.0085,
            "phase": 3.6,
            "edge": (110, 200, 240, 170),
            "body": (28, 70, 115),
            "depth": 190,
            "blur": 9,
        },
        {
            "base_y": 510,
            "amplitude": 50,
            "freq": 0.007,
            "phase": 1.2,
            "edge": (130, 215, 250, 200),
            "body": (30, 80, 130),
            "depth": 180,
            "blur": 8,
        },
        {
            "base_y": 620,
            "amplitude": 42,
            "freq": 0.0095,
            "phase": 5.0,
            "edge": (150, 225, 255, 225),
            "body": (35, 90, 140),
            "depth": 165,
            "blur": 7,
        },
        {
            "base_y": 740,
            "amplitude": 35,
            "freq": 0.008,
            "phase": 2.5,
            "edge": (175, 240, 255, 250),
            "body": (40, 100, 150),
            "depth": 150,
            "blur": 6,
        },
    ]

    for w in waves:
        y_func = lambda x, w=w: wave_y(
            x, w["base_y"], w["amplitude"], w["freq"], w["phase"]
        )
        content = draw_glass_wave(
            content, y_func, w["edge"], w["body"], w["depth"], w["blur"]
        )

    # Clip to rounded rect
    content.putalpha(mask)
    img = Image.alpha_composite(img, content)

    out_path = os.path.join(OUT_DIR, "icon_1024.png")
    img.save(out_path)
    print(f"Saved {out_path}")


if __name__ == "__main__":
    main()
