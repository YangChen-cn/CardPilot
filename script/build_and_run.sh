#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="CardPilot"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/CardPilot.app"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq '"CardPilot"'; then
  echo 'CardPilot 签名证书不可用。请在钥匙串访问中确认 CardPilot 有配对私钥，并将其「代码签名」信任设为「始终信任」。' >&2
  exit 1
fi
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodebuild -project CardPilot.xcodeproj -scheme CardPilotMac -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=CardPilot build -quiet
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "CardPilot"' ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.cardpilot.app.mac"' ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE" --args "${@:2}"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "CardPilot build and launch verified." ;;
  --demo|demo) /usr/bin/open -n "$APP_BUNDLE" --args --demo "${@:2}" ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--demo]" >&2; exit 2 ;;
esac
