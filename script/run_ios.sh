#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
DEVICE="${1:-iPhone 17}"
if (( $# > 0 )); then shift; fi
DEVICE_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; name=sys.argv[1]; matches=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"]==name or d["udid"]==name]; print(matches[0]["udid"] if matches else "")' "$DEVICE")"
if [[ -z "$DEVICE_ID" ]]; then echo "未找到模拟器：$DEVICE" >&2; exit 1; fi
xcodebuild -project CardPilot.xcodeproj -scheme CardPilotIOS -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/iOSDerivedData CODE_SIGNING_ALLOWED=NO build -quiet
if ! xcrun simctl list devices booted | /usr/bin/grep -Fq "$DEVICE_ID"; then xcrun simctl boot "$DEVICE_ID"; fi
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl terminate "$DEVICE_ID" com.cardpilot.app >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" build/iOSDerivedData/Build/Products/Debug-iphonesimulator/CardPilot.app
DEVELOPER_DIR_PATH="$(xcode-select -p)"
if [[ -d "$DEVELOPER_DIR_PATH/Applications/Simulator.app" ]]; then
    open "$DEVELOPER_DIR_PATH/Applications/Simulator.app" --args -CurrentDeviceUDID "$DEVICE_ID"
else
    open "${DEVELOPER_DIR_PATH%/Developer}/Applications/DeviceHub.app" --args -CurrentDeviceUDID "$DEVICE_ID"
fi
xcrun simctl launch "$DEVICE_ID" com.cardpilot.app "$@"
