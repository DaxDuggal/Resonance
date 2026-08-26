"""
One-off test: can Higgsfield's text-to-image model produce a usable pixel-art
sprite sheet? Not an official Higgsfield feature (their API is image/video/
audio/3D generation, no dedicated "sprite sheet" endpoint) — this just tests
whether prompting their flagship image model for a grid-of-frames layout
produces something clean enough to slice up in Godot, the way people
sometimes do with general-purpose image models.

Usage:
    pip install requests --break-system-packages
    python higgsfield_sprite_test.py

Reads credentials from .github/workflows/.env (HIGGSFIELD_KEY_ID,
HIGGSFIELD_API_KEY). Saves the result next to this script as
higgsfield_sprite_test_output.png/.jpg.
"""

import os
import time
import sys
from pathlib import Path

import requests

ENV_PATH = Path(__file__).parent / ".github" / "workflows" / ".env"


def load_env(path: Path) -> dict:
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


def main() -> None:
    env = load_env(ENV_PATH)
    key_id = env.get("HIGGSFIELD_KEY_ID")
    api_key = env.get("HIGGSFIELD_API_KEY")
    if not key_id or not api_key:
        sys.exit(f"Missing HIGGSFIELD_KEY_ID / HIGGSFIELD_API_KEY in {ENV_PATH}")

    headers = {
        "Authorization": f"Key {key_id}:{api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    prompt = (
        "2D pixel art character walk cycle sprite sheet, 4 frames in a single "
        "horizontal row, side view, small humanoid warrior character, "
        "transparent background, consistent proportions and palette across "
        "all frames, retro 16-bit metroidvania game style, clean pixel grid, "
        "no shading gradients, evenly spaced frames, no background scenery"
    )

    print("Submitting generation request...")
    resp = requests.post(
        "https://platform.higgsfield.ai/higgsfield-ai/soul/standard",
        headers=headers,
        json={"prompt": prompt, "aspect_ratio": "16:9", "resolution": "720p"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    status_url = data["status_url"]
    print(f"Queued: {data.get('request_id')}")

    print("Polling for completion...")
    while True:
        time.sleep(3)
        poll = requests.get(status_url, headers=headers, timeout=30)
        poll.raise_for_status()
        result = poll.json()
        status = result.get("status")
        print(f"  status={status}")
        if status in ("completed", "succeeded", "failed", "canceled", "error"):
            break

    if status not in ("completed", "succeeded"):
        sys.exit(f"Generation did not succeed: {result}")

    # Output shape varies by model; check a couple of likely spots.
    output_url = None
    for key in ("output", "outputs", "result", "results"):
        val = result.get(key)
        if isinstance(val, str):
            output_url = val
            break
        if isinstance(val, list) and val:
            first = val[0]
            output_url = first if isinstance(first, str) else first.get("url")
            break

    if not output_url:
        print("Couldn't find an output URL automatically. Full response:")
        print(result)
        sys.exit(1)

    ext = ".png" if ".png" in output_url else ".jpg"
    out_path = Path(__file__).parent / f"higgsfield_sprite_test_output{ext}"
    img = requests.get(output_url, timeout=60)
    img.raise_for_status()
    out_path.write_bytes(img.content)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
