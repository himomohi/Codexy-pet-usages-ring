from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build runtime pixel-potion frame and chamber mask assets.")
    parser.add_argument("--input", required=True, help="Chroma-key source generated from the visual reference.")
    parser.add_argument("--output-dir", required=True, help="Destination directory for runtime PNG assets.")
    parser.add_argument("--width", type=int, default=68)
    parser.add_argument("--height", type=int, default=73)
    parser.add_argument("--threshold", type=int, default=96)
    return parser.parse_args()


def is_key(pixel: tuple[int, int, int, int], key: tuple[int, int, int], threshold: int) -> bool:
    return max(abs(pixel[index] - key[index]) for index in range(3)) <= threshold


def remove_magenta_spill(red: int, green: int, blue: int) -> tuple[int, int, int]:
    """Neutralize chroma-key fringe without softening the pixel-art silhouette."""
    spill = ((red + blue) // 2) - green
    if red > 110 and blue > 70 and spill > 38:
        neutral = max(green, min(150, (red + green + blue) // 4))
        return neutral, neutral, neutral
    return red, green, blue


def flood_outside(key_pixels: list[list[bool]], width: int, height: int) -> list[list[bool]]:
    outside = [[False for _ in range(width)] for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= width or y >= height:
            continue
        if outside[y][x] or not key_pixels[y][x]:
            continue
        outside[y][x] = True
        queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
    return outside


def largest_component(mask: list[list[bool]], width: int, height: int) -> set[tuple[int, int]]:
    visited: set[tuple[int, int]] = set()
    largest: set[tuple[int, int]] = set()
    for y in range(height):
        for x in range(width):
            if not mask[y][x] or (x, y) in visited:
                continue
            component: set[tuple[int, int]] = set()
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited.add((x, y))
            while queue:
                cx, cy = queue.popleft()
                component.add((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and (nx, ny) not in visited:
                        visited.add((nx, ny))
                        queue.append((nx, ny))
            if len(component) > len(largest):
                largest = component
    return largest


def main() -> None:
    args = parse_args()
    source = Image.open(args.input).convert("RGBA")
    width, height = source.size
    key = source.getpixel((0, 0))[:3]
    pixels = source.load()
    key_pixels = [
        [is_key(pixels[x, y], key, args.threshold) for x in range(width)]
        for y in range(height)
    ]
    outside = flood_outside(key_pixels, width, height)
    enclosed = [
        [key_pixels[y][x] and not outside[y][x] for x in range(width)]
        for y in range(height)
    ]
    chamber = largest_component(enclosed, width, height)
    if not chamber:
        raise RuntimeError("No enclosed chroma-key chamber was found.")

    subject_points = [
        (x, y)
        for y in range(height)
        for x in range(width)
        if not key_pixels[y][x]
    ]
    if not subject_points:
        raise RuntimeError("No non-key potion frame pixels were found.")
    left = min(point[0] for point in subject_points)
    top = min(point[1] for point in subject_points)
    right = max(point[0] for point in subject_points) + 1
    bottom = max(point[1] for point in subject_points) + 1
    crop_box = (left, top, right, bottom)

    frame = Image.new("RGBA", source.size, (0, 0, 0, 0))
    frame_pixels = frame.load()
    for y in range(height):
        for x in range(width):
            if not key_pixels[y][x]:
                red, green, blue, _ = pixels[x, y]
                red, green, blue = remove_magenta_spill(red, green, blue)
                frame_pixels[x, y] = (red, green, blue, 255)

    mask = Image.new("RGBA", source.size, (255, 255, 255, 0))
    mask_pixels = mask.load()
    for x, y in chamber:
        mask_pixels[x, y] = (255, 255, 255, 255)

    size = (args.width, args.height)
    frame = frame.crop(crop_box).resize(size, Image.Resampling.NEAREST)
    mask = mask.crop(crop_box).resize(size, Image.Resampling.NEAREST)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    frame_path = output_dir / "potion-pixel-frame.png"
    mask_path = output_dir / "potion-pixel-mask.png"
    frame.save(frame_path, optimize=True)
    mask.save(mask_path, optimize=True)

    mask_alpha = mask.getchannel("A")
    mask_bounds = mask_alpha.getbbox()
    if mask_bounds is None:
        raise RuntimeError("Final chamber mask is empty.")
    print(f"frame={frame_path} size={frame.size}")
    print(f"mask={mask_path} bounds={mask_bounds}")


if __name__ == "__main__":
    main()
