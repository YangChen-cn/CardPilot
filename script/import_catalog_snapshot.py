#!/usr/bin/env python3
"""Import the canonical public Catalog V2 snapshot into the App fallback resources.

The public CardPilot-Catalog repository is the source of truth. This script
validates its catalog/image references, then atomically replaces
App/Resources/Catalog with the same snapshot for offline first launch.

Usage:
    python3 script/import_catalog_snapshot.py
    python3 script/import_catalog_snapshot.py --source ../CardPilot-Catalog/docs
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "build" / "CardPilot-Catalog" / "docs"
DEFAULT_DESTINATION = ROOT / "App" / "Resources" / "Catalog"
CONTENT_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
}


def fail(message: str) -> None:
    raise SystemExit(f"catalog import failed: {message}")


def safe_relative(path: str) -> Path:
    candidate = Path(path)
    if not path or candidate.is_absolute() or ".." in candidate.parts or "\\" in path:
        fail(f"unsafe asset path: {path!r}")
    if candidate.parts[0] == "":
        fail(f"unsafe asset path: {path!r}")
    return candidate


def validate_asset(asset: dict, source_root: Path) -> tuple[Path, Path]:
    if not isinstance(asset, dict):
        fail("asset must be an object")
    path = asset.get("path")
    digest = asset.get("sha256")
    content_type = asset.get("contentType")
    if not isinstance(path, str) or not isinstance(digest, str) or not isinstance(content_type, str):
        fail("asset path, sha256 and contentType are required strings")
    relative = safe_relative(path)
    expected_type = CONTENT_TYPES.get(relative.suffix.lower())
    if expected_type is None or expected_type != content_type.lower():
        fail(f"content type does not match extension: {path!r}")
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        fail(f"sha256 must be lowercase hex: {path!r}")
    source = source_root / relative
    if not source.is_file():
        fail(f"missing image: {source}")
    actual = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual != digest:
        fail(f"SHA-256 mismatch: {path!r}")
    return relative, source


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="directory containing catalog.json and images/")
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    args = parser.parse_args()
    source = args.source.resolve()
    destination = args.destination.resolve()
    catalog_path = source / "catalog.json"
    if not catalog_path.is_file():
        fail(f"missing catalog: {catalog_path}")
    try:
        document = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read catalog: {error}")
    if document.get("schemaVersion") != 2:
        fail("catalog must use schemaVersion 2")
    banks = document.get("banks")
    products = document.get("products")
    if not isinstance(banks, list) or not isinstance(products, list) or not banks or not products:
        fail("catalog must contain banks and products")

    assets: dict[str, tuple[Path, Path]] = {}
    for bank in banks:
        if not isinstance(bank, dict):
            fail("bank must be an object")
        if bank.get("logo") is not None:
            relative, source_image = validate_asset(bank["logo"], source)
            assets[str(relative)] = (relative, source_image)
    for product in products:
        if not isinstance(product, dict):
            fail("product must be an object")
        if product.get("artwork") is not None:
            relative, source_image = validate_asset(product["artwork"], source)
            assets[str(relative)] = (relative, source_image)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / f".Catalog.import-{uuid.uuid4().hex}"
    backup = destination.parent / f".Catalog.backup-{uuid.uuid4().hex}"
    try:
        temporary.mkdir()
        (temporary / "catalog.json").write_bytes(catalog_path.read_bytes())
        for relative, source_image in assets.values():
            target = temporary / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_image, target)
        if destination.exists():
            destination.rename(backup)
        temporary.rename(destination)
        if backup.exists():
            shutil.rmtree(backup)
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary, ignore_errors=True)
        if backup.exists() and not destination.exists():
            backup.rename(destination)
        raise
    print(f"imported {len(products)} products / {len(banks)} banks and {len(assets)} images into {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
