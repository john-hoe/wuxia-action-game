#!/usr/bin/env python3
"""Extract and apply a small RGB palette to an image."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    print("pip install Pillow numpy", file=sys.stderr)
    sys.exit(1)


def kmeans(pixels: np.ndarray, k: int, max_iter: int = 20) -> np.ndarray:
    """Cluster RGB pixels into k centroids using a small numpy K-means."""
    if k <= 0:
        raise ValueError("--colors must be greater than 0")
    if len(pixels) == 0:
        raise ValueError("input image has no pixels")

    rng = np.random.default_rng(42)
    replace = len(pixels) < k
    centroids = pixels[rng.choice(len(pixels), k, replace=replace)].astype(np.float64)
    pixels_float = pixels.astype(np.float64)

    for _ in range(max_iter):
        distances = np.sqrt(
            ((pixels_float[:, np.newaxis, :] - centroids[np.newaxis, :, :]) ** 2).sum(
                axis=2
            )
        )
        labels = np.argmin(distances, axis=1)
        new_centroids = np.array(
            [
                pixels_float[labels == i].mean(axis=0)
                if (labels == i).any()
                else centroids[i]
                for i in range(k)
            ]
        )
        if np.allclose(centroids, new_centroids):
            break
        centroids = new_centroids

    return centroids


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """Convert RGB values in 0..255 to CIELAB with D65 reference white."""
    rgb_normalized = rgb.astype(np.float64) / 255.0
    linear_rgb = np.where(
        rgb_normalized <= 0.04045,
        rgb_normalized / 12.92,
        ((rgb_normalized + 0.055) / 1.055) ** 2.4,
    )

    r = linear_rgb[..., 0]
    g = linear_rgb[..., 1]
    b = linear_rgb[..., 2]

    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    xn = 0.95047
    yn = 1.0
    zn = 1.08883

    fx = lab_f(x / xn)
    fy = lab_f(y / yn)
    fz = lab_f(z / zn)

    lab = np.empty_like(linear_rgb, dtype=np.float64)
    lab[..., 0] = 116.0 * fy - 16.0
    lab[..., 1] = 500.0 * (fx - fy)
    lab[..., 2] = 200.0 * (fy - fz)
    return lab


def lab_f(t: np.ndarray) -> np.ndarray:
    delta = 6.0 / 29.0
    return np.where(
        t > delta**3,
        np.cbrt(t),
        t / (3.0 * delta**2) + 4.0 / 29.0,
    )


def extract_palette(pixels: np.ndarray, color_count: int, source: Path) -> dict:
    centroids = kmeans(pixels, color_count)
    palette = np.clip(np.rint(centroids), 0, 255).astype(np.uint8)
    luminance = (
        0.2126 * palette[:, 0] + 0.7152 * palette[:, 1] + 0.0722 * palette[:, 2]
    )
    palette = palette[np.argsort(luminance)]

    return {
        "colors": palette.astype(int).tolist(),
        "count": int(color_count),
        "source": str(source),
    }


def save_palette(path: Path, palette_data: dict) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(palette_data, handle, indent=2)
        handle.write("\n")


def load_palette(path: Path) -> np.ndarray:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        raise
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid palette JSON: {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError("palette JSON must be an object")

    colors = data.get("colors")
    if not isinstance(colors, list) or not colors:
        raise ValueError("palette JSON must contain a non-empty 'colors' list")

    palette = np.array(colors, dtype=np.float64)
    if palette.ndim != 2 or palette.shape[1] != 3:
        raise ValueError("palette colors must be RGB triples")
    if np.any(palette < 0) or np.any(palette > 255):
        raise ValueError("palette colors must be in the 0..255 range")

    return np.rint(palette).astype(np.uint8)


def remap_pixels(pixels: np.ndarray, palette: np.ndarray) -> np.ndarray:
    pixels_lab = srgb_to_lab(pixels)
    palette_lab = srgb_to_lab(palette)
    distances = np.sqrt(
        ((pixels_lab[:, np.newaxis, :] - palette_lab[np.newaxis, :, :]) ** 2).sum(
            axis=2
        )
    )
    nearest = np.argmin(distances, axis=1)
    return palette[nearest]


def default_output_path(input_path: Path) -> Path:
    stem = input_path.stem if input_path.stem else input_path.name
    return input_path.with_name(f"{stem}_mapped.png")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract a K-means palette and remap image colors using CIELAB Delta-E."
    )
    parser.add_argument("input", type=Path, help="input image path")
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="output image path (default: input_mapped.png)",
    )
    parser.add_argument(
        "--palette",
        "-p",
        type=Path,
        default=Path("palette.json"),
        help="palette JSON path (default: palette.json)",
    )
    parser.add_argument(
        "--colors",
        "-c",
        type=int,
        default=32,
        help="number of palette colors (default: 32)",
    )
    parser.add_argument(
        "--extract-only",
        action="store_true",
        help="only extract palette, do not remap image",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.colors <= 0:
        print("Error: --colors must be greater than 0", file=sys.stderr)
        return 1

    input_path = args.input
    output_path = args.output if args.output is not None else default_output_path(input_path)

    try:
        with Image.open(input_path) as image:
            rgb_image = image.convert("RGB")
    except FileNotFoundError:
        print(f"Error: file not found: {input_path}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"Error: could not open image {input_path}: {exc}", file=sys.stderr)
        return 1

    pixels = np.array(rgb_image, dtype=np.uint8).reshape(-1, 3)

    try:
        if args.extract_only:
            palette_data = extract_palette(pixels, args.colors, input_path)
            save_palette(args.palette, palette_data)
            return 0

        if args.palette.exists():
            palette = load_palette(args.palette)
        else:
            palette_data = extract_palette(pixels, args.colors, input_path)
            save_palette(args.palette, palette_data)
            palette = np.array(palette_data["colors"], dtype=np.uint8)

        mapped_pixels = remap_pixels(pixels, palette)
        mapped_image = Image.fromarray(
            mapped_pixels.reshape(rgb_image.size[1], rgb_image.size[0], 3)
        )
        mapped_image.save(output_path, format="PNG")
    except (OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
