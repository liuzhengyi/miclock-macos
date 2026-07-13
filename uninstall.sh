#!/bin/zsh

set -euo pipefail

readonly LABEL="com.user.mic-input-lock"
readonly INSTALL_DIR="${MIC_INPUT_LOCK_INSTALL_DIR:-$HOME/.local/libexec/mic-input-lock}"
readonly CONFIG_DIR="${MIC_INPUT_LOCK_CONFIG_DIR:-$HOME/.config/mic-input-lock}"
readonly AGENTS_DIR="${MIC_INPUT_LOCK_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
readonly LOG_DIR="${MIC_INPUT_LOCK_LOG_DIR:-$HOME/Library/Logs}"
readonly PLIST_PATH="$AGENTS_DIR/$LABEL.plist"
readonly LAUNCHCTL="${LAUNCHCTL:-/bin/launchctl}"
readonly USER_ID="$(/usr/bin/id -u)"
readonly MENU_LABEL="com.user.mic-input-lock-menu"
readonly MENU_PLIST="$AGENTS_DIR/$MENU_LABEL.plist"
readonly MENU_APP="$HOME/Applications/MicLock.app"

purge_logs=0
if [[ "${1:-}" == "--purge-logs" ]]; then
  purge_logs=1
elif (( $# > 0 )); then
  /bin/echo "Usage: ./uninstall.sh [--purge-logs]" >&2
  exit 2
fi

"$LAUNCHCTL" bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
"$LAUNCHCTL" bootout "gui/$USER_ID" "$MENU_PLIST" 2>/dev/null || true
/bin/rm -f "$PLIST_PATH"
/bin/rm -f "$MENU_PLIST"
/bin/rm -rf "$INSTALL_DIR" "$CONFIG_DIR"
/bin/rm -rf "$MENU_APP"

if (( purge_logs )); then
  /bin/rm -f "$LOG_DIR/mic-input-lock.log" "$LOG_DIR/mic-input-lock.error.log"
fi

/bin/echo "Mic input lock removed. macOS can choose the default input normally again."
if (( ! purge_logs )); then
  /bin/echo "Logs were kept in $LOG_DIR (use --purge-logs to remove them)."
fi
