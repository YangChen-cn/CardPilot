#!/usr/bin/env python3
"""Add a public catalog image: re-encode it, strip metadata, print its JSON asset.

Usage:
    python3 script/catalog_asset.py IMAGE docs/images/cards/name.webp

Pillow is required. Images are always decoded and re-encoded to the requested
PNG/JPEG/WebP format, so EXIF/GPS/ICC metadata and the original file format are
not carried into the public catalog.
"""

from __future__ import annotations

import hashlib
import json
import sys
import uuid
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError as error:  # pragma: no cover - exercised by tool users
    raise SystemExit(
        "Pillow is required to import catalog images. Install it with: python3 -m pip install Pillow"
    ) from error


CONTENT_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}
FORMATS = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG", ".webp": "WEBP"}


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: catalog_asset.py IMAGE docs/images/cards/name.webp")
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    if not source.is_file():
        raise SystemExit(f"missing image: {source}")
    suffix = destination.suffix.lower()
    if suffix not in CONTENT_TYPES:
        raise SystemExit("destination must be .png, .jpg, .jpeg or .webp")
    destination.parent.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(source) as original:
            image = ImageOps.exif_transpose(original)
            image.load()
            if image.width > 2400 or image.height > 2400:
                raise SystemExit("image must be at most 2400px on each side")
            image.info = {}
            if suffix == ".png":
                encoded = image.convert("RGBA")
            elif suffix == ".webp":
                encoded = image.convert("RGBA")
            else:
                if image.mode in ("RGBA", "LA") or "transparency" in image.info:
                    background = Image.new("RGB", image.size, "white")
                    background.paste(image.convert("RGBA"), mask=image.convert("RGBA").getchannel("A"))
                    encoded = background
                else:
                    encoded = image.convert("RGB")
            encoded.info = {}
    except OSError as error:
        raise SystemExit(f"cannot decode image: {error}") from error

    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    try:
        if suffix == ".webp":
            encoded.save(temporary, "WEBP", quality=90, method=6)
        elif suffix == ".png":
            encoded.save(temporary, "PNG", optimize=True)
        else:
            encoded.save(temporary, "JPEG", quality=90, optimize=True)
        payload = temporary.read_bytes()
        if len(payload) > 4_000_000:
            raise SystemExit("image exceeds 4 MB")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)

    try:
        relative = destination.resolve().relative_to((Path.cwd() / "docs").resolve()).as_posix()
    except ValueError:
        relative = destination.as_posix()
    print(json.dumps({
        "path": relative,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "contentType": CONTENT_TYPES[suffix],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
