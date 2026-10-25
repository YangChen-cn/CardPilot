#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat >&2 <<'EOF'
usage: script/package_release.sh [all|mac|ios] [options]

Build Release artifacts without touching the running Debug app.
  --version VERSION   Override MARKETING_VERSION (default: project.yml)
  --build BUILD       Override CURRENT_PROJECT_VERSION (default: project.yml)
  --output DIR        Output directory (default: build/releases)

Environment:
  MAC_SIGN_IDENTITY   macOS signing identity (default: CardPilot)
  IOS_SIGN_IDENTITY   Optional iOS signing identity; empty produces an unsigned IPA

Output:
  build/releases/<version>/CardPilot-<version>.dmg
  build/releases/<version>/CardPilot-<version>.ipa
  build/releases/<version>/INSTALL.txt
  build/releases/<version>/*.sha256
EOF
}

TARGET=all
case "${1:-}" in
  all|mac|ios) TARGET="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage; exit 2 ;;
esac

VERSION=""
BUILD=""
OUTPUT="build/releases"
while (( $# > 0 )); do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
fi
if [[ -z "$BUILD" ]]; then
  BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)"
fi
if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "无法从 project.yml 读取版本号；请用 --version/--build 指定。" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "版本号包含不安全字符：$VERSION" >&2
  exit 2
fi

if [[ "$OUTPUT" != /* ]]; then OUTPUT="$ROOT_DIR/$OUTPUT"; fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
ARTIFACT_DIR="$OUTPUT/$VERSION"
STAGING="$OUTPUT/.staging-$VERSION"
ARCHIVES="$OUTPUT/archives"
LOGS="$OUTPUT/logs"
mkdir -p "$ARTIFACT_DIR" "$ARCHIVES" "$LOGS"
rm -rf "$STAGING"
mkdir -p "$STAGING"

MAC_SIGN_IDENTITY="${MAC_SIGN_IDENTITY:-CardPilot}"
IOS_SIGN_IDENTITY="${IOS_SIGN_IDENTITY:-}"

have_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "\"$1\""
}

run_archive() {
  local name="$1"; shift
  local log="$LOGS/$name.log"
  if ! xcodebuild "$@" >"$log" 2>&1; then
    echo "构建失败：$name；日志：$log" >&2
    tail -50 "$log" >&2
    exit 1
  fi
}

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

check_app_version() {
  local app="$1"
  local plist="$app/Info.plist"
  if [[ ! -f "$plist" ]]; then plist="$app/Contents/Info.plist"; fi
  local actual
  actual="$(read_plist "$plist" CFBundleShortVersionString)"
  if [[ "$actual" != "$VERSION" ]]; then
    echo "版本不匹配：期望 $VERSION，实际 ${actual:-<missing>}" >&2
    exit 1
  fi
}

write_sha() {
  local file="$1"
  (cd "$(dirname "$file")" && /usr/bin/shasum -a 256 "$(basename "$file")" > "$(basename "$file").sha256")
}

if [[ "$TARGET" == all || "$TARGET" == mac ]]; then
  rm -f "$ARTIFACT_DIR/CardPilot-$VERSION.dmg" "$ARTIFACT_DIR/CardPilot-$VERSION.dmg.sha256"
  if ! have_identity "$MAC_SIGN_IDENTITY"; then
    echo "macOS 签名证书不可用：$MAC_SIGN_IDENTITY" >&2
    echo "请确认钥匙串中存在代码签名证书与私钥，或设置 MAC_SIGN_IDENTITY。" >&2
    exit 1
  fi
  MAC_ARCHIVE="$ARCHIVES/CardPilot-$VERSION-mac.xcarchive"
  run_archive mac-archive \
    -project CardPilot.xcodeproj \
    -scheme CardPilotMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$MAC_ARCHIVE" \
    -derivedDataPath build/ReleaseDerivedData \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$MAC_SIGN_IDENTITY" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    archive
  MAC_APP="$MAC_ARCHIVE/Products/Applications/CardPilot.app"
  if [[ ! -d "$MAC_APP" ]]; then echo "未找到 macOS App：$MAC_APP" >&2; exit 1; fi
  check_app_version "$MAC_APP"
  /usr/bin/codesign --verify --deep --strict "$MAC_APP"
  MAC_STAGE="$STAGING/mac"
  mkdir -p "$MAC_STAGE"
  /usr/bin/ditto "$MAC_APP" "$MAC_STAGE/CardPilot.app"
  ln -s /Applications "$MAC_STAGE/Applications"
  DMG="$ARTIFACT_DIR/CardPilot-$VERSION.dmg"
  /usr/bin/hdiutil create -volname "CardPilot $VERSION" -srcfolder "$MAC_STAGE" -ov -format UDZO "$DMG" >/dev/null
  write_sha "$DMG"
  MAC_BUILT=1
  echo "macOS: $DMG"
fi

if [[ "$TARGET" == all || "$TARGET" == ios ]]; then
  rm -f "$ARTIFACT_DIR/CardPilot-$VERSION.ipa" "$ARTIFACT_DIR/CardPilot-$VERSION.ipa.sha256"
  if [[ -n "$IOS_SIGN_IDENTITY" ]] && ! have_identity "$IOS_SIGN_IDENTITY"; then
    echo "iOS 签名证书不可用：$IOS_SIGN_IDENTITY" >&2
    exit 1
  fi
  IOS_ARCHIVE="$ARCHIVES/CardPilot-$VERSION-ios.xcarchive"
  run_archive ios-archive \
    -project CardPilot.xcodeproj \
    -scheme CardPilotIOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$IOS_ARCHIVE" \
    -derivedDataPath build/ReleaseDerivedData \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    archive
  IOS_APP="$IOS_ARCHIVE/Products/Applications/CardPilot.app"
  if [[ ! -d "$IOS_APP" ]]; then echo "未找到 iOS App：$IOS_APP" >&2; exit 1; fi
  check_app_version "$IOS_APP"
  if /usr/bin/find "$IOS_APP" -name 'Mac-Info.plist' -print -quit | /usr/bin/grep -q .; then
    echo "iOS App 仍包含 Mac-Info.plist" >&2
    exit 1
  fi
  if [[ -n "$IOS_SIGN_IDENTITY" ]]; then
    /usr/bin/codesign --force --deep --sign "$IOS_SIGN_IDENTITY" --timestamp=none "$IOS_APP"
    /usr/bin/codesign --verify --deep --strict "$IOS_APP"
  fi
  IOS_STAGE="$STAGING/ios"
  mkdir -p "$IOS_STAGE/Payload"
  /usr/bin/ditto "$IOS_APP" "$IOS_STAGE/Payload/CardPilot.app"
  IPA="$ARTIFACT_DIR/CardPilot-$VERSION.ipa"
  (cd "$IOS_STAGE" && /usr/bin/zip -qry -X "$IPA" Payload)
  if /usr/bin/unzip -Z1 "$IPA" | /usr/bin/grep -Eq '^(__MACOSX/|Payload/CardPilot.app/Mac-Info.plist$)'; then
    echo "IPA 包含不应发布的文件" >&2
    exit 1
  fi
  if [[ -n "$IOS_SIGN_IDENTITY" ]]; then
    echo "iOS: $IPA (signed: $IOS_SIGN_IDENTITY)"
  else
    echo "iOS: $IPA (unsigned; re-sign before installing)"
  fi
  write_sha "$IPA"
  IOS_BUILT=1
fi

{
  echo "CardPilot $VERSION (build $BUILD)"
  echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  if [[ "${MAC_BUILT:-0}" == 1 ]]; then
    echo "macOS"
    echo "- Open CardPilot-$VERSION.dmg and drag CardPilot.app to Applications."
    echo "- Minimum macOS version: 26.0."
    echo "- This build is self-signed and not notarized; Gatekeeper may require"
    echo "  Control-click > Open on first launch."
    echo
  fi
  if [[ "${IOS_BUILT:-0}" == 1 ]]; then
    echo "iOS"
    if [[ -n "$IOS_SIGN_IDENTITY" ]]; then
      echo "- CardPilot-$VERSION.ipa is signed with $IOS_SIGN_IDENTITY."
    else
      echo "- CardPilot-$VERSION.ipa is unsigned."
    fi
    echo "- It is not an App Store or TestFlight build. Re-sign with your own"
    echo "  certificate/profile using Sideloadly, AltStore, or Xcode before installing."
    echo "- Minimum iOS version: 26.0."
    echo
  fi
  echo "SHA-256 checksums are next to each artifact. Review them before installing."
} > "$ARTIFACT_DIR/INSTALL.txt"

echo
echo "Release artifacts: $ARTIFACT_DIR"
ls -lh "$ARTIFACT_DIR"
for f in "$ARTIFACT_DIR"/*.sha256; do [[ -e "$f" ]] && cat "$f"; done
