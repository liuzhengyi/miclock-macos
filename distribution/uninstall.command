#!/bin/zsh

set -euo pipefail

readonly USER_ID="$(/usr/bin/id -u)"
readonly AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly LOCK_PLIST="$AGENTS_DIR/com.user.mic-input-lock.plist"
readonly MENU_PLIST="$AGENTS_DIR/com.user.mic-input-lock-menu.plist"

/bin/echo "正在卸载 MicLock…"
/bin/launchctl bootout "gui/$USER_ID" "$LOCK_PLIST" 2>/dev/null || true
/bin/launchctl bootout "gui/$USER_ID" "$MENU_PLIST" 2>/dev/null || true
/bin/rm -f "$LOCK_PLIST" "$MENU_PLIST"
/bin/rm -rf "$HOME/Applications/MicLock.app"
/bin/rm -rf "$HOME/.local/libexec/mic-input-lock" "$HOME/.config/mic-input-lock"
for name in miclock mic-on mic-off mic-status mic-list mic-fix mic-pick mic-set mic-quit mic-start; do
  /bin/rm -f "$HOME/.local/bin/$name"
done
/bin/rm -f \
  "$HOME/Library/Logs/mic-input-lock.log" \
  "$HOME/Library/Logs/mic-input-lock.error.log" \
  "$HOME/Library/Logs/mic-input-lock-menu.log" \
  "$HOME/Library/Logs/mic-input-lock-menu.error.log"
/bin/echo "MicLock 已卸载，macOS 将恢复原本的默认输入选择行为。"
if [[ -t 0 ]]; then
  /bin/echo -n "按回车键关闭此窗口…"
  read -r
fi
