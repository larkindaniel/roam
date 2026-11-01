#!/usr/bin/env python3
"""Generates the original artwork used as sample place photos. Needs Pillow; its output is committed,
so only rerun it to change the art. Nothing here is a real or stock photograph."""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1200, 800
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "supabase", "fixtures", "photos")

# key: (scene, sky top, sky bottom, accent)
PLACES = {
    "harbor": ("cafe", "#f2b880", "#fbe3c0", "#c8553d"), "saltmarsh": ("coast", "#7fb7c9", "#e8e0c9", "#2f5d6b"),
    "cedar": ("peaks", "#8fb8d8", "#e6eef2", "#2f5a46"), "willow": ("coast", "#a3cfc4", "#f0ead2", "#3d7a68"),
    "quay": ("city", "#9fb1c4", "#e7e3d8", "#3e4c5e"), "moonline": ("night", "#1b1740", "#51307a", "#f2a65a"),
    "kite": ("coast", "#6fc3df", "#f6f1d5", "#e4572e"), "aster": ("city", "#e9b7a8", "#f7e6d4", "#6e3b3b"),
    "tidewater": ("night", "#23304f", "#7a3e5d", "#f7c548"), "gull": ("coast", "#94b4c1", "#ece5d5", "#40514e"),
    "rosebud": ("night", "#2c1432", "#8a2846", "#ffb4a2"), "lookout": ("peaks", "#f4a896", "#fce5c8", "#5b4a68"),
    "fjord": ("peaks", "#b6d7e8", "#f0f6f7", "#5c7f93"), "coral": ("coast", "#55c1c9", "#f8eecb", "#1f7a8c"),
    "lumen": ("cafe", "#f6c453", "#fdeab5", "#b5442e"), "fig": ("cafe", "#d9a679", "#f4dfc6", "#6b3f2a"),
    "lagoon": ("coast", "#8fd3d1", "#eef4ec", "#2a7f83"), "juniper": ("peaks", "#7da7c7", "#e8e4d6", "#37533f"),
    "tiles": ("city", "#7fa6d6", "#f1ece0", "#27477a"), "miradouro": ("city", "#f7b267", "#fde4c3", "#b2543b"),
    "alfama": ("night", "#20264a", "#a0475b", "#ffd166"), "bica": ("cafe", "#e6a15c", "#f8dfbd", "#7a3f22"),
}


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(draw, top, bottom):
    for y in range(HEIGHT):
        draw.line([(0, y), (WIDTH, y)], fill=mix(top, bottom, y / HEIGHT))


def ridge(draw, rng, base, amplitude, color):
    points, x, y = [(0, HEIGHT)], 0, base
    while x <= WIDTH + 60:
        points.append((x, y))
        x += rng.randint(50, 130)
        y = base + rng.randint(-amplitude, amplitude)
    draw.polygon(points + [(WIDTH, HEIGHT)], fill=color)


def buildings(draw, rng, base, color, lit):
    x = -20
    while x < WIDTH:
        width, top = rng.randint(90, 190), base - rng.randint(120, 380)
        draw.rectangle([x, top, x + width, HEIGHT], fill=mix(color, (255, 255, 255), rng.random() * 0.15))
        for wy in range(top + 24, HEIGHT - 30, 54):
            for wx in range(x + 16, x + width - 22, 40):
                if rng.random() < 0.65:
                    draw.rectangle([wx, wy, wx + 18, wy + 28], fill=lit)
        x += width + rng.randint(0, 12)


def paint(key, scene, top, bottom, accent):
    rng = random.Random(key)
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    top, bottom, accent = rgb(top), rgb(bottom), rgb(accent)
    sky(draw, top, bottom)
    sun = (rng.randint(150, WIDTH - 150), rng.randint(90, 280))
    radius = rng.randint(45, 85)
    draw.ellipse([sun[0] - radius, sun[1] - radius, sun[0] + radius, sun[1] + radius], fill=mix(bottom, (255, 255, 255), 0.6))
    if scene == "peaks":
        for index, base in enumerate((400, 500, 610)):
            ridge(draw, rng, base, 95 - index * 18, mix(bottom, accent, 0.45 + index * 0.27))
    elif scene == "coast":
        ridge(draw, rng, 410, 35, mix(bottom, accent, 0.55))
        for y in range(470, HEIGHT, 6):
            draw.line([(0, y), (WIDTH, y)], fill=mix(accent, top, 0.15 + rng.random() * 0.2))
        for _ in range(4):
            x, y = rng.randint(60, WIDTH - 120), rng.randint(520, 720)
            draw.polygon([(x, y), (x + 80, y), (x + 62, y + 20), (x + 16, y + 20)], fill=(250, 246, 235))
            draw.polygon([(x + 36, y - 66), (x + 36, y - 4), (x + 74, y - 4)], fill=(255, 255, 255))
    elif scene == "city":
        buildings(draw, rng, 470, mix(bottom, accent, 0.5), mix(accent, (255, 255, 255), 0.25))
        buildings(draw, rng, 690, accent, mix(top, (255, 255, 255), 0.45))
    elif scene == "night":
        for _ in range(90):
            x, y = rng.randint(0, WIDTH), rng.randint(0, 330)
            draw.point([(x, y), (x + 1, y)], fill=(255, 250, 225))
        buildings(draw, rng, 630, mix(top, (0, 0, 0), 0.35), accent)
    else:
        draw.rectangle([0, 560, WIDTH, HEIGHT], fill=mix(accent, (40, 25, 15), 0.3))
        draw.rectangle([0, 150, WIDTH, 180], fill=accent)
        for x in range(90, WIDTH, 250):
            draw.line([(x, 165), (x, 290)], fill=(60, 45, 35), width=3)
            draw.ellipse([x - 34, 280, x + 34, 348], fill=mix(accent, (255, 230, 170), 0.75))
            draw.rectangle([x - 62, 500, x + 62, 520], fill=mix(accent, (255, 255, 255), 0.45))
            draw.rectangle([x - 6, 520, x + 6, 640], fill=(50, 35, 25))
    image = image.filter(ImageFilter.GaussianBlur(0.8))
    grain = Image.effect_noise((WIDTH, HEIGHT), 9).convert("RGB")
    return Image.blend(image, grain, 0.05)


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, spec in PLACES.items():
        paint(key, *spec).save(os.path.join(OUT, key + ".jpg"), quality=82)


if __name__ == "__main__":
    main()
