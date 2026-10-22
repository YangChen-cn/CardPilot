#!/usr/bin/env python3
"""Publish the bundled Catalog V2 snapshot to the public catalog repository.

Usage:
    python3 script/build_catalog_snapshot.py \
        --output build/CardPilot-Catalog/docs/catalog.json \
        --content-version 2026102302 --published-at 2026-10-23

The bundled catalog is the source of truth. This script copies its referenced
images and writes a public JSON snapshot; it never reads personal SwiftData.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "App" / "Resources" / "Catalog" / "catalog.json"


def fail(message: str) -> None:
    raise SystemExit(f"catalog build failed: {message}")


def parse_date(value: str) -> None:
    try:
        date.fromisoformat(value)
    except ValueError:
        fail(f"publishedAt must be YYYY-MM-DD: {value!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--content-version", required=True, type=int)
    parser.add_argument("--published-at", required=True)
    parser.add_argument("--skip-images", action="store_true")
    args = parser.parse_args()
    if args.content_version <= 0:
        fail("contentVersion must be positive")
    parse_date(args.published_at)
    data = json.loads(args.catalog.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 2:
        fail("bundled catalog must use schemaVersion 2")
    if not data.get("banks") or not data.get("products"):
        fail("bundled catalog has no banks or products")

    output_root = args.output.parent
    image_root = args.catalog.parent
    seen: set[str] = set()
    for bank in data["banks"]:
        path = bank["logo"]["path"]
        if path in seen:
            continue
        seen.add(path)
        source = image_root / path
        if not source.is_file():
            fail(f"missing bundled image: {source}")
        if hashlib.sha256(source.read_bytes()).hexdigest() != bank["logo"]["sha256"]:
            fail(f"SHA-256 mismatch: {source}")
        if not args.skip_images:
            target = output_root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for product in data["products"]:
        path = product["artwork"]["path"]
        if path in seen:
            continue
        seen.add(path)
        source = image_root / path
        if not source.is_file():
            fail(f"missing bundled image: {source}")
        if hashlib.sha256(source.read_bytes()).hexdigest() != product["artwork"]["sha256"]:
            fail(f"SHA-256 mismatch: {source}")
        if not args.skip_images:
            target = output_root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    data["contentVersion"] = args.content_version
    data["publishedAt"] = args.published_at
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(args.output)
    print(f"wrote {len(data['products'])} products / {len(data['banks'])} banks and {len(seen)} images")
    return 0


if __name__ == "__main__":
    sys.exit(main())
