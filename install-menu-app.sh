#!/bin/zsh

set -euo pipefail

readonly LABEL="com.user.mic-input-lock-menu"
readonly SOURCE_DIR="${0:A:h}"
readonly APP_PATH="${MIC_LOCK_MENU_APP_PATH:-$HOME/Applications/MicLock.app}"
readonly AGENTS_DIR="${MIC_INPUT_LOCK_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
readonly PLIST_PATH="$AGENTS_DIR/$LABEL.plist"
readonly LOG_DIR="${MIC_INPUT_LOCK_LOG_DIR:-$HOME/Library/Logs}"
readonly USER_ID="$(/usr/bin/id -u)"

[[ -x "$HOME/.local/bin/miclock" ]] || {
  /bin/echo "ERROR: install the miclock command first" >&2
  exit 1
}
build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mic-lock-menu.XXXXXX")"
temp_plist="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mic-lock-menu.XXXXXX.plist")"
trap '/bin/rm -rf "$build_dir"; /bin/rm -f "$temp_plist"' EXIT

stage_app="$build_dir/MicLock.app"
/bin/mkdir -p "$HOME/Applications" "$AGENTS_DIR" "$LOG_DIR"
"$SOURCE_DIR/build-menu-app.sh" "$stage_app"
/usr/bin/ditto --noextattr --noqtn --noacl "$stage_app" "$APP_PATH"

# The app is normally launched by launchd through its inner executable. Register
# the bundle explicitly so Launch Services and Spotlight can find "MicLock".
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -f "$APP_PATH"

/bin/cp "$SOURCE_DIR/menu-app/com.user.mic-input-lock-menu.plist.template" "$temp_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$APP_PATH/Contents/MacOS/MicLockMenu" "$temp_plist"
/usr/bin/plutil -replace StandardOutPath -string "$LOG_DIR/mic-input-lock-menu.log" "$temp_plist"
/usr/bin/plutil -replace StandardErrorPath -string "$LOG_DIR/mic-input-lock-menu.error.log" "$temp_plist"
/usr/bin/plutil -lint "$temp_plist" >/dev/null
/usr/bin/install -m 644 "$temp_plist" "$PLIST_PATH"

/bin/launchctl bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$USER_ID" "$PLIST_PATH"
/bin/launchctl enable "gui/$USER_ID/$LABEL"
/bin/launchctl kickstart -k "gui/$USER_ID/$LABEL"

/bin/sleep 1
if /bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
  /bin/echo "MicLock menu bar app installed and running: $APP_PATH"
else
  /bin/echo "ERROR: menu bar app did not start" >&2
  exit 1
fi
