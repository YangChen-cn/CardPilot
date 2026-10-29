# CardPilot Public Artwork Notes

> 这是公开仓库的卡面与资料库约定。原内部协作约定保存在本地未跟踪的根目录 `AGENTS.md`，不会进入公开提交。

## Card artwork

- Use horizontal card artwork for the catalog and the app's shared card slot. The canonical aspect ratio is approximately **1.586:1** (for example 1200×756 or 1600×1009).
- Never commit a real card face containing a full card number, a partial card number, a cardholder name, an expiry date, or any other personal data. Personal card images belong only in the user's SwiftData store and private folder sync.
- For `CardPilot-Catalog`, replace the image, update its `sha256` and `contentType`, increase `contentVersion`, then run `scripts/validate_catalog.py` before publishing.
- Prefer a native horizontal render from the bank. Rotating a portrait render by 90° is a migration fallback only when no horizontal source exists; review the result for readability before publishing.
- If the user explicitly authorizes image generation when suitable horizontal art is unavailable, use the official image as a reference and clearly label the result as a generated illustration in product notes and the source record. Preserve bank/network/tier identity; never present it as an official issued card face or infer benefits from the image. Bank logos still come from official assets.
- After changing the public catalog, import it into the app with `script/import_catalog_snapshot.py` and verify that the image count and hashes match.

## Product data

- Before submitting a Catalog PR, read the [Catalog PR checklist](https://github.com/YangChen-cn/CardPilot-Catalog/blob/main/docs/pr-submission.md). Validate the actual client field types as well as catalog syntax; `merchantKeywords` is a comma-separated string, not an array.
- Do not weaken SwiftData migrations or replace a user's local ledger to make a release compatible.
- Keep personal offer state, card artwork, transactions, and sync metadata out of the public catalog repository.

## 真正横版构图（2026-10-29）

卡面本身必须横版铺满1200×756画布。禁止将竖图缩小后居中置入透明或白色横版画布来凑尺寸，禁止拉伸、旋转文字。找不到合适官方横版时，用户已授权以官方素材为参考，通过imagegen重排为横版示意；核对银行、卡组织、等级和主要图案，不添加个人字段。按用户2026-10-29最新要求，产品说明和App界面不显示AI卡面标注；仅在素材来源文档记录生成示意身份、官方参考和提示词，独立银行Logo仍使用官方资源。发布前查看最终素材的实际构图；尺寸及哈希通过不能替代此检查。
