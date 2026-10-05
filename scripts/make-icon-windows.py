"""Render the macOS icon motif with Windows chrome. Requires Pillow.

Run: python scripts/make-icon-windows.py
"""
from pathlib import Path
from math import cos, sin, pi
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "apps/windows/Rotatorring/Resources"


def render(size):
    # Draw each size separately at 4x resolution, simplifying small details.
    scale = size * 4 / 1024
    n = size * 4
    small = size <= 32
    def box(values):
        return tuple(round(v * scale) for v in values)
    def width(value):
        return max(1, round(value * scale))
    image = Image.new("RGBA", (n, n))
    mask = Image.new("L", (n, n))
    ImageDraw.Draw(mask).rounded_rectangle(box((48, 48, 976, 976)), radius=width(96), fill=255)
    gradient = Image.new("RGBA", (n, n))
    pixels = gradient.load()
    colors = [(255, 138, 92), (224, 69, 123), (91, 42, 134)]
    for y in range(n):
        for x in range(n):
            t = max(0, min(1, (x + y) / (2 * (n - 1)))) * 2
            i = min(1, int(t))
            f = t - i
            pixels[x, y] = tuple(round(a + (b - a) * f) for a, b in zip(colors[i], colors[i + 1])) + (255,)
    image.paste(gradient, (0, 0), mask)
    draw = ImageDraw.Draw(image)
    if not small:
        # Ghost of the original horizontal window, behind the rotated one.
        for x in range(226, 790, 62):
            for y in (350, 730):
                draw.line(box((x, y, min(x + 36, 798), y)), fill="#ffffff80", width=width(12))
        for y in range(350, 730, 62):
            for x in (226, 798):
                draw.line(box((x, y, x, min(y + 36, 730))), fill="#ffffff80", width=width(12))
    # Clockwise arc and arrow, matching the original icon's direction.
    points = [(512 + 350 * cos(a), 512 + 350 * sin(a))
              for a in [-pi * .56 + i * pi * .46 / 80 for i in range(81)]]
    draw.line([box(p) for p in points], fill="white", width=width(42 if small else 34), joint="curve")
    x, y = points[0]
    r = 21 if small else 17
    draw.ellipse(box((x-r, y-r, x+r, y+r)), fill="white")
    a = -pi * .1
    x, y = points[-1]
    tx, ty, nx, ny = -sin(a), cos(a), cos(a), sin(a)
    draw.polygon([box((x+tx*74, y+ty*74)), box((x+nx*56, y+ny*56)),
                  box((x-nx*56, y-ny*56))], fill="white")
    window = Image.new("RGBA", (n, n))
    wd = ImageDraw.Draw(window)
    wd.rounded_rectangle(box((222, 342, 802, 742)), radius=width(22), fill="white")
    wd.rounded_rectangle(box((222, 342, 802, 426)), radius=width(22), fill="#ffe4ea")
    wd.rectangle(box((222, 384, 802, 426)), fill="#ffe4ea")
    # Native Windows caption symbols replace the macOS traffic-light dots.
    ink = "#5b2a86"
    if not small:
        wd.line(box((600, 387, 626, 387)), fill=ink, width=width(6))
        wd.rectangle(box((666, 369, 690, 393)), outline=ink, width=width(6))
    wd.line(box((736, 369, 760, 393)), fill=ink, width=width(8))
    wd.line(box((760, 369, 736, 393)), fill=ink, width=width(8))
    window = window.rotate(-180 / 7, resample=Image.Resampling.BICUBIC, center=box((512, 512)))
    image.alpha_composite(window)
    return image.resize((size, size), Image.Resampling.LANCZOS)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    frames = [render(size) for size in sizes]
    frames[-1].save(OUTPUT / "AppIcon.ico", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
    render(256).save(OUTPUT / "AppIcon.png")
    print(f"Wrote Windows icon and preview to {OUTPUT}")
