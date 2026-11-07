#!/usr/bin/env python3
"""Generate JP the Cat's paw-lick animation with the Higgsfield API."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "brand" / "jp-cat-yellow-icon-2048.png"
DEFAULT_PROMPT = ROOT / "brand" / "jp-cat-paw-lick-purr.prompt.txt"
DEFAULT_OUTPUT = ROOT / "brand" / "generated" / "jp-cat-paw-lick-purr.mp4"
DEFAULT_MODEL = "higgsfield-ai/dop/standard"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload JP's source image to Higgsfield and download the generated MP4.",
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="Local source image.")
    parser.add_argument("--prompt-file", type=Path, default=DEFAULT_PROMPT, help="Prompt text file.")
    parser.add_argument("--prompt", help="Inline prompt override. Defaults to --prompt-file.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help="Output MP4 path.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Higgsfield model id.")
    parser.add_argument("--duration", type=int, default=5, help="Requested video duration in seconds.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the request payload without uploading or generating.",
    )
    return parser.parse_args()


def require_source(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise SystemExit(f"Source image not found: {resolved}")
    content_type, _ = mimetypes.guess_type(str(resolved))
    if content_type is None or not content_type.startswith("image/"):
        raise SystemExit(f"Source is not a recognized image: {resolved}")
    return resolved


def read_prompt(args: argparse.Namespace) -> str:
    if args.prompt:
        prompt = args.prompt
    else:
        prompt_path = args.prompt_file.expanduser().resolve()
        if not prompt_path.is_file():
            raise SystemExit(f"Prompt file not found: {prompt_path}")
        prompt = prompt_path.read_text(encoding="utf-8")
    prompt = " ".join(prompt.split())
    if not prompt:
        raise SystemExit("Prompt is empty.")
    return prompt


def has_credentials() -> bool:
    if os.environ.get("HIGGSFIELD_KEY") and not os.environ.get("HF_KEY"):
        os.environ["HF_KEY"] = os.environ["HIGGSFIELD_KEY"]
    if os.environ.get("HF_CREDENTIALS") and not os.environ.get("HF_KEY"):
        os.environ["HF_KEY"] = os.environ["HF_CREDENTIALS"]
    if os.environ.get("HIGGSFIELD_API_KEY") and not os.environ.get("HF_API_KEY"):
        os.environ["HF_API_KEY"] = os.environ["HIGGSFIELD_API_KEY"]
    if os.environ.get("HIGGSFIELD_API_SECRET") and not os.environ.get("HF_API_SECRET"):
        os.environ["HF_API_SECRET"] = os.environ["HIGGSFIELD_API_SECRET"]
    return bool(os.environ.get("HF_KEY")) or bool(os.environ.get("HF_API_KEY") and os.environ.get("HF_API_SECRET"))


def load_client() -> Any:
    if not has_credentials():
        raise SystemExit(
            "Missing Higgsfield credentials. Set HF_KEY='key:secret' or both "
            "HF_API_KEY and HF_API_SECRET, then rerun this script."
        )

    try:
        import higgsfield_client  # type: ignore[import-not-found]
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "Missing Python package 'higgsfield-client'. Install it with: "
            "python3 -m pip install higgsfield-client"
        ) from exc
    return higgsfield_client


def extract_video_url(result: dict[str, Any]) -> str:
    video = result.get("video")
    if isinstance(video, dict) and isinstance(video.get("url"), str):
        return video["url"]

    videos = result.get("videos")
    if isinstance(videos, list):
        for item in videos:
            if isinstance(item, dict) and isinstance(item.get("url"), str):
                return item["url"]

    jobs = result.get("jobs")
    if isinstance(jobs, list):
        for job in jobs:
            raw = job.get("results", {}).get("raw") if isinstance(job, dict) else None
            if isinstance(raw, dict) and isinstance(raw.get("url"), str):
                return raw["url"]

    raise SystemExit(f"Higgsfield response did not include a video URL:\n{json.dumps(result, indent=2)}")


def download(url: str, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "JPtheCat-Higgsfield-Asset-Generator/1.0"})
    with urllib.request.urlopen(request, timeout=300) as response:
        out.write_bytes(response.read())


def main() -> int:
    args = parse_args()
    source = require_source(args.source)
    prompt = read_prompt(args)
    out = args.out.expanduser().resolve()
    payload = {
        "image_url": "<uploaded by higgsfield_client.upload_file>",
        "prompt": prompt,
        "duration": args.duration,
    }

    if args.dry_run:
        print(
            json.dumps(
                {
                    "model": args.model,
                    "source": str(source),
                    "output": str(out),
                    "arguments": payload,
                },
                indent=2,
            )
        )
        return 0

    client = load_client()

    print(f"Uploading source image: {source}")
    image_url = client.upload_file(str(source))
    payload["image_url"] = image_url

    print(f"Submitting Higgsfield job: {args.model}")
    result = client.subscribe(
        args.model,
        arguments=payload,
        on_enqueue=lambda request_id: print(f"Queued request: {request_id}"),
        on_queue_update=lambda status: print(f"Status: {status}"),
    )

    video_url = extract_video_url(result)
    print(f"Downloading video: {video_url}")
    download(video_url, out)

    metadata_path = out.with_suffix(".higgsfield.json")
    metadata_path.write_text(
        json.dumps(
            {
                "model": args.model,
                "source": str(source),
                "output": str(out),
                "arguments": payload,
                "result": result,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"Wrote {out}")
    print(f"Wrote {metadata_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
