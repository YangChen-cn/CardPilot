#!/usr/bin/env python3
"""Add a public catalog image: copy it, strip metadata, and print its JSON asset.

Usage:
    python3 script/catalog_asset.py IMAGE docs/images/cards/name.webp

The script uses Pillow when available to normalize EXIF and re-encode the image.
It never reads personal data; only the given image file is used.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: catalog_asset.py IMAGE docs/images/cards/name.webp")
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    if not source.is_file():
        raise SystemExit(f"missing image: {source}")
    suffix = destination.suffix.lower()
    content_types = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}
    if suffix not in content_types:
        raise SystemExit("destination must be .png, .jpg, .jpeg or .webp")
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        from PIL import Image
        with Image.open(source) as image:
            image.load()
            if image.width > 2400 or image.height > 2400:
                raise SystemExit("image must be at most 2400px on each side")
            if suffix == ".webp":
                image.convert("RGBA").save(destination, "WEBP", quality=90, method=6)
            elif suffix == ".png":
                image.convert("RGBA").save(destination, "PNG", optimize=True)
            else:
                image.convert("RGB").save(destination, "JPEG", quality=90, optimize=True)
    except ImportError:
        shutil.copy2(source, destination)
    payload = destination.read_bytes()
    if len(payload) > 4_000_000:
        raise SystemExit("image exceeds 4 MB")
    print(json.dumps({
        "path": destination.as_posix().split("docs/", 1)[-1],
        "sha256": hashlib.sha256(payload).hexdigest(),
        "contentType": content_types[suffix],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
