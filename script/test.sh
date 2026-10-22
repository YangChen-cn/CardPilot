#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq '"CardPilot"'; then
  echo 'CardPilot 签名证书不可用。请先在钥匙串访问中确认私钥及代码签名信任。' >&2
  exit 1
fi
# Tests may re-sign their host app. Keep them away from the bundle open for the user.
xcodebuild -project CardPilot.xcodeproj -scheme CardPilotMac -destination 'platform=macOS,arch=arm64' -derivedDataPath build/TestDerivedData CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=CardPilot test "$@"
