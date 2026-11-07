#!/usr/bin/env python3
"""Create transparent-alpha versions of the JP Higgsfield animation."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "brand" / "generated" / "jp-cat-paw-lick-purr.mp4"
DEFAULT_OUTDIR = ROOT / "brand" / "generated" / "transparent"
DEFAULT_OUTPUT_STEM = "jp-cat-paw-lick-purr-transparent"


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def probe_fps(input_path: Path) -> str:
    output = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=r_frame_rate",
            "-of",
            "json",
            str(input_path),
        ],
        text=True,
    )
    data = json.loads(output)
    return data["streams"][0]["r_frame_rate"]


def estimate_circle(frame_path: Path, radius_pad: float) -> tuple[float, float, float]:
    image = Image.open(frame_path).convert("RGB")
    arr = np.asarray(image)
    h, w = arr.shape[:2]
    yy, xx = np.ogrid[:h, :w]
    cx = w / 2
    cy = h / 2
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    white = (r > 220) & (g > 210) & (b > 175) & (dist > min(w, h) * 0.28)

    ys, xs = np.where(white)
    if len(xs) < 100:
        return cx, cy, min(w, h) * 0.455

    xmin, xmax = float(xs.min()), float(xs.max())
    ymin, ymax = float(ys.min()), float(ys.max())
    cx = (xmin + xmax) / 2
    cy = (ymin + ymax) / 2
    radius = max(xmax - xmin, ymax - ymin) / 2 + radius_pad
    return cx, cy, radius


def alpha_for_frame(image: Image.Image, cx: float, cy: float, radius: float, feather: float) -> Image.Image:
    rgb = image.convert("RGB")
    arr = np.asarray(rgb)
    h, w = arr.shape[:2]
    yy, xx = np.ogrid[:h, :w]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    circle_alpha = np.clip((radius + feather - dist) / feather, 0, 1) * 255

    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)

    # Outside the circle, remove the smooth yellow field while preserving the
    # non-background silhouette that protrudes past the ring: tail, feet, paws.
    yellow_background = (r > 165) & (g > 115) & (b < 120) & (r > g + 8) & (g > b + 35)
    outside_circle = dist > (radius - 8)
    subject = outside_circle & ~yellow_background

    subject_mask = Image.fromarray((subject.astype(np.uint8) * 255))
    subject_alpha = subject_mask.filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.MaxFilter(7)).filter(
        ImageFilter.GaussianBlur(1.2)
    )

    alpha = np.maximum(circle_alpha.astype(np.uint8), np.asarray(subject_alpha))
    rgba = np.dstack([arr, alpha])
    return Image.fromarray(rgba)


def composite_checker(frame: Image.Image, tile: int = 32) -> Image.Image:
    w, h = frame.size
    yy, xx = np.ogrid[:h, :w]
    checker = ((xx // tile + yy // tile) % 2).astype(np.uint8)
    bg = np.where(checker[:, :, None] == 0, 238, 190).astype(np.uint8)
    bg_image = Image.fromarray(np.repeat(bg, 3, axis=2)).convert("RGBA")
    bg_image.alpha_composite(frame)
    return bg_image.convert("RGB")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    parser.add_argument("--circle-center-x", type=float)
    parser.add_argument("--circle-center-y", type=float)
    parser.add_argument("--circle-radius", type=float)
    parser.add_argument("--radius-pad", type=float, default=8)
    parser.add_argument("--feather", type=float, default=3)
    parser.add_argument(
        "--output-stem",
        default=DEFAULT_OUTPUT_STEM,
        help="Base filename for the .mov and .webm alpha exports.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = args.input.expanduser().resolve()
    outdir = args.outdir.expanduser().resolve()
    if not input_path.is_file():
        raise SystemExit(f"Input video not found: {input_path}")

    raw_dir = outdir / "raw-frames"
    rgba_dir = outdir / "rgba-frames"
    preview_dir = outdir / "previews"
    for path in (raw_dir, rgba_dir, preview_dir):
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True)

    fps = probe_fps(input_path)
    run(["ffmpeg", "-y", "-i", str(input_path), "-map", "0:v:0", str(raw_dir / "frame_%04d.png")])

    raw_frames = sorted(raw_dir.glob("frame_*.png"))
    if not raw_frames:
        raise SystemExit("No frames extracted.")

    sample = raw_frames[len(raw_frames) // 2]
    cx, cy, radius = estimate_circle(sample, args.radius_pad)
    if args.circle_center_x is not None:
        cx = args.circle_center_x
    if args.circle_center_y is not None:
        cy = args.circle_center_y
    if args.circle_radius is not None:
        radius = args.circle_radius

    for index, frame_path in enumerate(raw_frames, start=1):
        rgba = alpha_for_frame(Image.open(frame_path), cx, cy, radius, args.feather)
        rgba.save(rgba_dir / f"frame_{index:04d}.png")
        if index in {1, len(raw_frames) // 2, len(raw_frames)}:
            composite_checker(rgba).save(preview_dir / f"preview_{index:04d}.jpg", quality=95)

    output_stem = Path(args.output_stem).name
    mov_out = outdir / f"{output_stem}.mov"
    webm_out = outdir / f"{output_stem}.webm"

    run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            fps,
            "-i",
            str(rgba_dir / "frame_%04d.png"),
            "-i",
            str(input_path),
            "-map",
            "0:v:0",
            "-map",
            "1:a?",
            "-c:v",
            "prores_ks",
            "-profile:v",
            "4",
            "-pix_fmt",
            "yuva444p10le",
            "-c:a",
            "copy",
            "-shortest",
            str(mov_out),
        ]
    )

    run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            fps,
            "-i",
            str(rgba_dir / "frame_%04d.png"),
            "-i",
            str(input_path),
            "-map",
            "0:v:0",
            "-map",
            "1:a?",
            "-c:v",
            "libvpx-vp9",
            "-pix_fmt",
            "yuva420p",
            "-auto-alt-ref",
            "0",
            "-b:v",
            "0",
            "-crf",
            "28",
            "-c:a",
            "libopus",
            "-shortest",
            str(webm_out),
        ]
    )

    shutil.rmtree(raw_dir)
    shutil.rmtree(rgba_dir)

    print(f"Circle mask: center=({cx:.1f}, {cy:.1f}) radius={radius:.1f}")
    print(mov_out)
    print(webm_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
