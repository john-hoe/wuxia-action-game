#!/usr/bin/env python3
"""Batch import AI-generated images into Godot asset directories."""

from __future__ import annotations

import argparse
import collections
import sys
import time
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image, UnidentifiedImageError
except ImportError:  # pragma: no cover - depends on local environment
    print("Error: Pillow is required. pip install Pillow", file=sys.stderr)
    sys.exit(1)


IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}


def parse_size(value: str) -> tuple[int, int]:
    """Parse a size in WxH format."""
    parts = value.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("size must be in WxH format, e.g. 512x512")

    try:
        width, height = (int(part) for part in parts)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("size width and height must be integers") from exc

    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("size width and height must be positive")

    return width, height


def parse_hex_color(value: str) -> tuple[int, int, int]:
    """Parse a 6-digit RGB hex color."""
    raw = value.strip().removeprefix("#")
    if len(raw) != 6:
        raise argparse.ArgumentTypeError("chroma color must be a 6-digit hex RGB value")

    try:
        return int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("chroma color must be a valid hex RGB value") from exc


def parse_tolerance(value: str) -> int:
    """Parse a color tolerance in the inclusive range 0-255."""
    try:
        tolerance = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("tolerance must be an integer") from exc

    if tolerance < 0 or tolerance > 255:
        raise argparse.ArgumentTypeError("tolerance must be between 0 and 255")

    return tolerance


def parse_category(value: str) -> str:
    """Parse an output category as a relative subdirectory."""
    if not value.strip():
        raise argparse.ArgumentTypeError("category must be a relative subdirectory under output")

    path = Path(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise argparse.ArgumentTypeError("category must be a relative subdirectory under output")

    return value


def is_image_file(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS


def iter_image_files(input_dir: Path) -> Iterable[Path]:
    for path in sorted(input_dir.iterdir()):
        if is_image_file(path):
            yield path


def floodfill_remove_bg(img: Image.Image, tolerance: int = 20) -> None:
    """Remove background by flood-filling from all 4 corners."""
    pixels = img.load()
    width, height = img.size
    corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    visited: set[tuple[int, int]] = set()
    queue = collections.deque(corners)

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or x < 0 or x >= width or y < 0 or y >= height:
            continue

        visited.add((x, y))
        r, g, b, _a = pixels[x, y]

        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nx < 0 or nx >= width or ny < 0 or ny >= height or (nx, ny) in visited:
                continue

            nr, ng, nb, _na = pixels[nx, ny]
            if abs(nr - r) <= tolerance and abs(ng - g) <= tolerance and abs(nb - b) <= tolerance:
                queue.append((nx, ny))

    for x, y in visited:
        r, g, b, _a = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)


def chroma_remove_bg(img: Image.Image, chroma_color: tuple[int, int, int], tolerance: int) -> None:
    """Replace pixels near chroma_color with transparent."""
    pixels = img.load()
    width, height = img.size
    cr, cg, cb = chroma_color

    for y in range(height):
        for x in range(width):
            r, g, b, _a = pixels[x, y]
            if abs(r - cr) <= tolerance and abs(g - cg) <= tolerance and abs(b - cb) <= tolerance:
                pixels[x, y] = (r, g, b, 0)


def center_crop_to_aspect(img: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    """Center-crop an image to match the target aspect ratio."""
    target_width, target_height = target_size
    width, height = img.size
    source_ratio = width / height
    target_ratio = target_width / target_height

    if source_ratio > target_ratio:
        crop_width = max(1, round(height * target_ratio))
        left = (width - crop_width) // 2
        return img.crop((left, 0, left + crop_width, height))

    if source_ratio < target_ratio:
        crop_height = max(1, round(width / target_ratio))
        top = (height - crop_height) // 2
        return img.crop((0, top, width, top + crop_height))

    return img


def resize_center_crop(img: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    cropped = center_crop_to_aspect(img, target_size)
    return cropped.resize(target_size, Image.Resampling.LANCZOS)


def output_path_for(source_path: Path, output_dir: Path, category: str | None) -> Path:
    target_dir = output_dir / category if category else output_dir
    return target_dir / f"{source_path.stem}.png"


def target_dir_for(output_dir: Path, category: str | None) -> Path:
    return output_dir / category if category else output_dir


def output_is_current(source_path: Path, target_path: Path) -> bool:
    return target_path.exists() and target_path.stat().st_mtime >= source_path.stat().st_mtime


def process_image(
    source_path: Path,
    output_dir: Path,
    target_size: tuple[int, int],
    mode: str,
    category: str | None,
    chroma_color: tuple[int, int, int],
    chroma_tolerance: int,
) -> bool:
    target_path = output_path_for(source_path, output_dir, category)
    if output_is_current(source_path, target_path):
        return False

    try:
        with Image.open(source_path) as opened:
            img = opened.convert("RGBA")
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        print(f"Warning: skipping corrupt image {source_path}: {exc}", file=sys.stderr)
        return False

    if mode == "floodfill":
        floodfill_remove_bg(img)
    elif mode == "chroma":
        chroma_remove_bg(img, chroma_color, chroma_tolerance)

    img = resize_center_crop(img, target_size)

    target_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(target_path, "PNG")
    print(f"Imported: {source_path.name} -> {target_path}")
    return True


def wait_for_stable_file(path: Path, checks: int = 3, interval: float = 0.2) -> None:
    """Give copied files a short window to finish writing before opening them."""
    last_size = -1
    stable_checks = 0

    while stable_checks < checks:
        try:
            current_size = path.stat().st_size
        except FileNotFoundError:
            return

        if current_size == last_size:
            stable_checks += 1
        else:
            stable_checks = 0
            last_size = current_size

        time.sleep(interval)


def run_once(args: argparse.Namespace) -> None:
    for source_path in iter_image_files(args.input_dir):
        process_image(
            source_path,
            args.output,
            args.size,
            args.mode,
            args.category,
            args.chroma_color,
            args.chroma_tolerance,
        )


def run_watch(args: argparse.Namespace) -> None:
    try:
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer
    except ImportError:
        print("pip install watchdog", file=sys.stderr)
        sys.exit(1)

    class ImportHandler(FileSystemEventHandler):
        def process_path(self, path_text: str) -> None:
            source_path = Path(path_text)
            if not is_image_file(source_path):
                return

            wait_for_stable_file(source_path)
            process_image(
                source_path,
                args.output,
                args.size,
                args.mode,
                args.category,
                args.chroma_color,
                args.chroma_tolerance,
            )

        def on_created(self, event) -> None:  # type: ignore[no-untyped-def]
            if not event.is_directory:
                self.process_path(event.src_path)

        def on_moved(self, event) -> None:  # type: ignore[no-untyped-def]
            if not event.is_directory:
                self.process_path(event.dest_path)

    run_once(args)

    observer = Observer()
    observer.schedule(ImportHandler(), str(args.input_dir), recursive=False)
    observer.start()
    print(f"Watching: {args.input_dir}")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()

    observer.join()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Process AI-generated images and copy them into Godot asset directories.",
    )
    parser.add_argument("input_dir", type=Path, help="Directory to process")
    parser.add_argument("-o", "--output", type=Path, default=Path("assets"), help="Output base directory")
    parser.add_argument("-s", "--size", type=parse_size, default=parse_size("512x512"), help="Target size WxH")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("floodfill", "chroma", "none"),
        default="chroma",
        help="Background removal mode",
    )
    parser.add_argument("-w", "--watch", action="store_true", help="Monitor input_dir for new files")
    parser.add_argument("-c", "--category", type=parse_category, help="Target subdirectory under assets/")
    parser.add_argument(
        "--chroma-color",
        type=parse_hex_color,
        default=parse_hex_color("00ff00"),
        help="Hex color for chroma key",
    )
    parser.add_argument(
        "--chroma-tolerance",
        type=parse_tolerance,
        default=30,
        help="Tolerance 0-255",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.input_dir.is_dir():
        print(f"Error: input directory not found: {args.input_dir}", file=sys.stderr)
        return 1

    target_dir_for(args.output, args.category).mkdir(parents=True, exist_ok=True)

    if args.watch:
        run_watch(args)
    else:
        run_once(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())
