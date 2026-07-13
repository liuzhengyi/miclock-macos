#!/bin/zsh

set -euo pipefail

readonly LABEL="com.user.mic-input-lock-menu"
readonly APP_PATH="${MIC_LOCK_MENU_APP_PATH:-$HOME/Applications/MicLock.app}"
readonly PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly USER_ID="$(/usr/bin/id -u)"

/bin/launchctl bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
/bin/rm -f "$PLIST_PATH"
/bin/rm -rf "$APP_PATH"
/bin/echo "MicLock menu bar app removed. The microphone lock service was left unchanged."
