#!/usr/bin/env python3
"""Build the public, versioned catalog snapshot from the bundled bank library.

Usage:
    python3 script/build_catalog_snapshot.py --output build/catalog.json \
        --content-version 2026102201 --published-at 2026-10-22

Only official product/offer data is written. User cards, transactions, account
numbers, credentials and local edits are never read by this script.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "App" / "Resources"
MANIFESTS = [RESOURCES / "BankLibrary" / "hsbc-products.json",
             RESOURCES / "BankLibrary" / "bochk-bea-products.json",
             RESOURCES / "BankLibrary" / "cncbi-products.json"]
HTTPS = re.compile(r"^https://[^\s]+$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def fail(message: str) -> None:
    raise SystemExit(f"catalog build failed: {message}")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path}: {error}")


def parse_date(value: str, label: str) -> None:
    if not DATE.fullmatch(value):
        fail(f"{label} must be YYYY-MM-DD: {value!r}")
    try:
        date.fromisoformat(value)
    except ValueError:
        fail(f"{label} is not a valid date: {value!r}")


def strip_image_payload(card: dict) -> dict:
    # Artwork is shipped in the app bundle. The remote snapshot only carries
    # official terms so the repository stays small and has no personal data.
    card.pop("imageURL", None)
    card.pop("imageBase64", None)
    return card


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--content-version", required=True, type=int)
    parser.add_argument("--published-at", required=True)
    args = parser.parse_args()

    if args.content_version <= 0:
        fail("content version must be a positive integer")
    parse_date(args.published_at, "publishedAt")

    package_cache: dict[str, dict] = {}
    products: list[dict] = []
    seen: set[str] = set()
    for manifest_path in MANIFESTS:
        manifest = load_json(manifest_path)
        for definition in manifest.get("products", []):
            product_id = definition.get("id", "")
            if not product_id or product_id in seen:
                fail(f"duplicate or empty product id: {product_id!r}")
            seen.add(product_id)

            resource = definition.get("catalogResource", "")
            if not resource:
                fail(f"{product_id}: missing catalogResource")
            if resource not in package_cache:
                package_cache[resource] = load_json(RESOURCES / f"{resource}.json")
            package = package_cache[resource]
            card = next((item for item in package.get("cards", []) if item.get("id") == product_id), None)
            if card is None:
                fail(f"{product_id}: catalog card not found")
            if package.get("schemaVersion") != 1:
                fail(f"{product_id}: unsupported catalog schema")
            for field in ("sourceURL",):
                if not HTTPS.fullmatch(card.get(field, "")):
                    fail(f"{product_id}: {field} must be HTTPS")
            parse_date(card.get("verifiedOn", ""), f"{product_id} verifiedOn")
            for rule in card.get("rules", []):
                if not HTTPS.fullmatch(rule.get("sourceURL", "")):
                    fail(f"{product_id}/{rule.get('id')}: sourceURL must be HTTPS")
                parse_date(rule.get("startsOn", ""), f"{product_id}/{rule.get('id')} startsOn")
                parse_date(rule.get("endsOn", ""), f"{product_id}/{rule.get('id')} endsOn")

            plans = definition.get("welcomePlans", [])
            rule_ids = {rule.get("id") for rule in card.get("rules", [])}
            for plan in plans:
                if not HTTPS.fullmatch(plan.get("sourceURL", "")):
                    fail(f"{product_id}/{plan.get('id')}: plan sourceURL must be HTTPS")
                if plan.get("ruleIDs") and not set(plan["ruleIDs"]).issubset(rule_ids):
                    fail(f"{product_id}/{plan.get('id')}: plan references missing rule")
                for field in ("applicationStartsOn", "applicationEndsOn"):
                    if plan.get(field):
                        parse_date(plan[field], f"{product_id}/{plan.get('id')} {field}")

            products.append({
                "id": product_id,
                "bankID": definition.get("bankID", ""),
                "imageResource": definition.get("imageResource", ""),
                "baseRewardVerified": bool(definition.get("baseRewardVerified", False)),
                "welcomePlans": plans,
                "catalog": strip_image_payload(dict(card)),
            })

    if not products:
        fail("no products found")
    if len({product["bankID"] for product in products}) != 4 or {product["bankID"] for product in products} != {"hsbc", "bochk", "bea", "cncbi"}:
        fail("expected exactly the hsbc, bochk, bea and cncbi banks")

    document = {
        "schemaVersion": 1,
        "contentVersion": args.content_version,
        "publishedAt": args.published_at,
        "products": products,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(products)} products to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
