#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="${SRCROOT:?Run this script from the Xcode build phase.}"
DEST_DIR="${TARGET_BUILD_DIR:?}/${EXECUTABLE_FOLDER_PATH:?}"
DEST="$DEST_DIR/CardPilotMailKeychain"
STAMP="${TARGET_TEMP_DIR:?}/CardPilotMailKeychain.inputs"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-CardPilot}"
if [[ "$IDENTITY" == '-' ]]; then echo 'CardPilotMailKeychain requires the CardPilot certificate.' >&2; exit 1; fi
SOURCES=("$ROOT_DIR/Support/MailKeychain/MailKeychainMain.swift" "$ROOT_DIR/App/Services/Mail/MailKeychainMessage.swift" "$ROOT_DIR/App/Services/Mail/MailKeychainReply.swift")
ENTITLEMENTS="$ROOT_DIR/Support/MailKeychain/MailKeychain.entitlements"
INPUT_HASH="$( {
  shasum -a 256 "${SOURCES[@]}" "$ENTITLEMENTS" "$ROOT_DIR/script/build_mail_keychain_helper.sh"
  xcrun --sdk macosx swiftc --version
  printf '%s\n' "$IDENTITY" "${ARCHS:?}" "${MACOSX_DEPLOYMENT_TARGET:?}" "${SDKROOT:?}"
} | shasum -a 256 | cut -d ' ' -f 1)"
if [[ -x "$DEST" && -f "$STAMP" && "$(cat "$STAMP")" == "$INPUT_HASH" ]] && /usr/bin/codesign --verify --strict "$DEST" 2>/dev/null; then
  exit 0
fi
mkdir -p "$DEST_DIR"
TASK_DIR="$(mktemp -d "${TARGET_TEMP_DIR}/mail-keychain.XXXXXX")"
trap 'rm -rf "$TASK_DIR"' EXIT
BINARIES=()
for ARCH in $ARCHS; do
  BIN="$TASK_DIR/helper-$ARCH"
  xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -O -module-name CardPilotMailKeychain \
    -target "$ARCH-apple-macosx$MACOSX_DEPLOYMENT_TARGET" "${SOURCES[@]}" -o "$BIN"
  BINARIES+=("$BIN")
done
if [[ "${#BINARIES[@]}" -eq 1 ]]; then cp "${BINARIES[0]}" "$DEST"; else xcrun lipo -create "${BINARIES[@]}" -output "$DEST"; fi
chmod 755 "$DEST"
/usr/bin/codesign --force --sign "$IDENTITY" --identifier com.cardpilot.mail-keychain --timestamp=none --entitlements "$ENTITLEMENTS" "$DEST"
/usr/bin/codesign --verify --strict "$DEST"
printf '%s' "$INPUT_HASH" > "$STAMP"
