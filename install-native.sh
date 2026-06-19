#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/CodexResets.xcodeproj"
TARGET="Traice"
DERIVED_DATA="${TRAICE_DERIVED_DATA:-/tmp/traice-derived-data}"
APP_BUNDLE_ID="${TRAICE_APP_BUNDLE_ID:-com.juicecolored.traice}"
WIDGET_BUNDLE_ID="${TRAICE_WIDGET_BUNDLE_ID:-$APP_BUNDLE_ID.widget}"
LAUNCH_AGENT_LABEL="${TRAICE_LAUNCH_AGENT_LABEL:-$APP_BUNDLE_ID}"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Traice.app"
BUILT_WIDGET_APPEX="$BUILT_APP/Contents/PlugIns/Traice Widget.appex"
APP_PATH="${1:-$HOME/Applications/Traice.app}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
WIDGET_APPEX="$APP_PATH/Contents/PlugIns/Traice Widget.appex"
WIDGET_ENTITLEMENTS="$SCRIPT_DIR/Sources/CodexResetsWidget/CodexResetsWidget.entitlements"

mkdir -p "$(dirname "$APP_PATH")" "$HOME/Library/LaunchAgents"

xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$TARGET" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  TRAICE_APP_BUNDLE_ID="$APP_BUNDLE_ID" \
  TRAICE_WIDGET_BUNDLE_ID="$WIDGET_BUNDLE_ID" \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  build

rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"

if command -v codesign >/dev/null 2>&1; then
  if [[ -d "$WIDGET_APPEX" ]]; then
    codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET_APPEX" >/dev/null
  fi
  codesign --force --sign - "$APP_PATH" >/dev/null
fi

if [[ -d "$WIDGET_APPEX" ]] && command -v pluginkit >/dev/null 2>&1; then
  if [[ -d "$BUILT_WIDGET_APPEX" ]]; then
    pluginkit -r "$BUILT_WIDGET_APPEX" >/dev/null 2>&1 || true
  fi
  pluginkit -a "$WIDGET_APPEX" >/dev/null 2>&1 || true
  pluginkit -e use -i "$WIDGET_BUNDLE_ID" >/dev/null 2>&1 || true
fi

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCH_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-na</string>
    <string>$APP_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/traice.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/traice.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
pkill -f "Traice.app/Contents/MacOS" >/dev/null 2>&1 || true
pkill -f "Traice" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL"

echo "Installed and launched $APP_PATH"
echo "Start-at-login LaunchAgent: $LAUNCH_AGENT"
echo "Notification Center widget: Traice"
