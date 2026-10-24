#!/usr/bin/env python3
"""Render ergon's raster branding from ergon-emblem.svg.

Outputs (committed, so the image build needs none of these tools):
  wallpapers/ergon-dark.jpg, wallpapers/ergon-light.jpg   3840x2160 desktop wallpapers
  plymouth/watermark.png                                  boot splash emblem
  fastfetch/logo.txt                                      terminal logo (half-block characters)

Needs ImageMagick (with librsvg), numpy, scipy and Pillow:  python3 branding/generate.py
"""

import pathlib
import subprocess
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = pathlib.Path(__file__).resolve().parent
SVG = (HERE / "ergon-emblem.svg").read_text()

# Logo colours
TERRACOTTA = (0xC8, 0x60, 0x3F)
CHARCOAL = (0x24, 0x24, 0x2D)

W, H = 3840, 2160


def rasterize(height, recolor=None):
    """Emblem as an RGBA float array (0..1) of the given pixel height.

    recolor maps the SVG's fill colours to replacements, e.g. to get a single-shape mask.
    """
    svg = SVG
    for old, new in (recolor or {}).items():
        svg = svg.replace(f'fill="{old}"', f'fill="{new}"')
    with tempfile.TemporaryDirectory() as tmp:
        src, out = pathlib.Path(tmp, "e.svg"), pathlib.Path(tmp, "e.png")
        src.write_text(svg)
        subprocess.run(
            ["magick", "-background", "none", "-density", "600", str(src),
             "-resize", f"x{height}", str(out)],
            check=True,
        )
        return np.asarray(Image.open(out).convert("RGBA"), dtype=np.float64) / 255.0


def place(layer, cx, cy):
    """Paste a small RGBA array into a full-canvas transparent array, centred on (cx, cy)."""
    canvas = np.zeros((H, W, 4))
    h, w = layer.shape[:2]
    x, y = int(cx - w / 2), int(cy - h / 2)
    canvas[y:y + h, x:x + w] = layer
    return canvas


def over(base, color, alpha):
    """Composite a flat colour onto base (H, W, 3) with a per-pixel alpha (H, W)."""
    c = np.asarray(color, dtype=np.float64) / 255.0
    a = np.clip(alpha, 0, 1)[..., None]
    return base * (1 - a) + c * a


def gradient(top, bottom):
    t = np.linspace(0, 1, H)[:, None, None]
    top, bottom = (np.asarray(c, dtype=np.float64) / 255.0 for c in (top, bottom))
    return np.broadcast_to(top * (1 - t) + bottom * t, (H, W, 3)).copy()


def wallpaper(path, top, bottom, ring_alpha, glow_alpha, vignette):
    img = gradient(top, bottom)
    cx, cy = W / 2, H * 0.5
    emblem_h = int(H * 0.30)

    emblem = place(rasterize(emblem_h), cx, cy)
    # The whole outer shape (shield + flame) as one mask, for the rings and glow.
    shield = place(rasterize(emblem_h, {"#24242D": "#C8603F"}), cx, cy)[..., 3]

    # Contour lines echoing the shield outline outwards, fading with distance.
    dist = ndimage.distance_transform_edt(shield < 0.5)
    spacing, width = 72.0, 1.6
    phase = np.abs((dist + spacing / 2) % spacing - spacing / 2)
    line = np.clip(1 - (phase - width / 2), 0, 1) * (dist > spacing / 2)
    falloff = np.exp(-dist / 520.0)
    img = over(img, TERRACOTTA, line * falloff * ring_alpha)

    # Warm glow behind the emblem.
    glow = ndimage.gaussian_filter(shield, sigma=140)
    img = over(img, TERRACOTTA, glow / glow.max() * glow_alpha)

    # Soft drop shadow, then the emblem itself.
    shadow = ndimage.gaussian_filter(ndimage.shift(shield, (18, 0)), sigma=28)
    img = over(img, (0, 0, 0), shadow * 0.35)
    a = emblem[..., 3:4]
    img = img * (1 - a) + emblem[..., :3] * a

    # Vignette and a little noise so the gradients don't band.
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot((xx - cx) / (W / 2), (yy - cy) / (H / 2))
    img = over(img, (0, 0, 0), np.clip(r - 0.55, 0, None) ** 2 * vignette)
    rng = np.random.default_rng(1)
    img += rng.normal(0, 0.8 / 255, img.shape)

    out = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8))
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, quality=92, subsampling=0, optimize=True)
    print(path.relative_to(HERE))


def plymouth_watermark(path, height=144):
    out = Image.fromarray((rasterize(height) * 255 + 0.5).astype(np.uint8), "RGBA")
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, optimize=True)
    print(path.relative_to(HERE))


def terminal_logo(path, rows=16):
    """Emblem as half-block text art: each character cell holds two square pixels.

    Only the terracotta shape is drawn (in truecolor); the flame is left empty so the terminal's
    own background shows through it, as the charcoal does on the real logo. The outer shape is
    made exactly symmetrical, which rounding to so few pixels otherwise breaks.
    """
    sub = 8  # supersampling per output pixel
    outline = rasterize(rows * 2 * sub)[..., 3]
    flame = rasterize(rows * 2 * sub, {"#C8603F": "none"})[..., 3]

    # Crop to the shape and pad evenly, so its centre line falls on the pixel grid.
    cols = np.flatnonzero(outline.max(axis=0) > 0.01)
    outline, flame = outline[:, cols[0]:cols[-1] + 1], flame[:, cols[0]:cols[-1] + 1]
    pad = -outline.shape[1] % sub
    padding = ((0, 0), (pad // 2, pad - pad // 2))
    outline, flame = np.pad(outline, padding), np.pad(flame, padding)

    def downsample(a):
        h, w = a.shape
        return a.reshape(h // sub, sub, w // sub, sub).mean(axis=(1, 3))

    shape = downsample(outline)
    shape = (shape + shape[:, ::-1]) / 2 > 0.5
    pixels = shape & ~(downsample(flame) > 0.5)

    r, g, b = TERRACOTTA
    blocks = {(True, True): "\u2588", (True, False): "\u2580", (False, True): "\u2584", (False, False): " "}
    lines = []
    for top, bottom in zip(pixels[0::2], pixels[1::2]):
        text = "".join(blocks[bool(t), bool(u)] for t, u in zip(top, bottom))
        lines.append(f"\x1b[38;2;{r};{g};{b}m{text}\x1b[0m")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    print(path.relative_to(HERE))


if __name__ == "__main__":
    wallpaper(HERE / "wallpapers/ergon-dark.jpg", (0x2A, 0x2A, 0x34), (0x15, 0x15, 0x1B),
              ring_alpha=0.42, glow_alpha=0.26, vignette=0.55)
    wallpaper(HERE / "wallpapers/ergon-light.jpg", (0xF5, 0xEF, 0xE9), (0xE4, 0xD9, 0xCF),
              ring_alpha=0.32, glow_alpha=0.16, vignette=0.12)
    plymouth_watermark(HERE / "plymouth/watermark.png")
    terminal_logo(HERE / "fastfetch/logo.txt")
