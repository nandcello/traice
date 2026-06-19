#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="${TRAICE_APP_BUNDLE_ID:-com.juicecolored.traice}"
WIDGET_BUNDLE_ID="${TRAICE_WIDGET_BUNDLE_ID:-$APP_BUNDLE_ID.widget}"
LAUNCH_AGENT_LABEL="${TRAICE_LAUNCH_AGENT_LABEL:-$APP_BUNDLE_ID}"
APP_PATH="${1:-$HOME/Applications/Traice.app}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
WIDGET_APPEX="$APP_PATH/Contents/PlugIns/Traice Widget.appex"

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
pkill -f "Traice.app/Contents/MacOS" >/dev/null 2>&1 || true

if [[ -d "$WIDGET_APPEX" ]] && command -v pluginkit >/dev/null 2>&1; then
  pluginkit -e ignore -i "$WIDGET_BUNDLE_ID" >/dev/null 2>&1 || true
  pluginkit -r "$WIDGET_APPEX" >/dev/null 2>&1 || true
fi

rm -f "$LAUNCH_AGENT"
rm -rf "$APP_PATH"

echo "Removed Traice menu bar app and widget extension."
