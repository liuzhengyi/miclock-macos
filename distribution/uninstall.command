#!/bin/zsh

set -euo pipefail

readonly APP_PATH="$HOME/Applications/MicLock.app"
readonly APP_BINARY="$APP_PATH/Contents/MacOS/MicLock"
readonly BIN_DIR="$HOME/.local/bin"
readonly SUPPORT_DIR="$HOME/Library/Application Support/MicLock"
readonly MANIFEST="$SUPPORT_DIR/managed-commands.txt"
readonly USER_ID="$(/usr/bin/id -u)"
readonly LEGACY_LOCK_PLIST="$HOME/Library/LaunchAgents/com.user.mic-input-lock.plist"
readonly LEGACY_MENU_PLIST="$HOME/Library/LaunchAgents/com.user.mic-input-lock-menu.plist"
readonly LEGACY_INSTALL_DIR="$HOME/.local/libexec/mic-input-lock"
readonly LEGACY_CONFIG_DIR="$HOME/.config/mic-input-lock"
readonly WRAPPER_MARKER="# Managed by MicLock io.github.liuzhengyi.miclock"

[[ "$USER_ID" != "0" ]] || {
  /bin/echo "ERROR: 请不要使用 sudo 或 root 卸载 MicLock" >&2
  exit 1
}

/bin/echo "正在卸载 MicLock…"
if [[ -x "$APP_BINARY" ]]; then
  "$APP_BINARY" --cli login-off >/dev/null 2>&1 || true
  "$APP_BINARY" --cli quit >/dev/null 2>&1 || true
fi

/bin/launchctl bootout "gui/$USER_ID" "$LEGACY_LOCK_PLIST" 2>/dev/null || true
/bin/launchctl bootout "gui/$USER_ID" "$LEGACY_MENU_PLIST" 2>/dev/null || true
/bin/rm -f "$LEGACY_LOCK_PLIST" "$LEGACY_MENU_PLIST"

commands=()
if [[ -r "$MANIFEST" ]]; then
  while IFS= read -r name; do
    [[ "$name" == miclock || "$name" == mic-* ]] && commands+=("$name")
  done < "$MANIFEST"
else
  commands=(miclock mic-on mic-off mic-status mic-list mic-fix mic-pick mic-set mic-quit mic-start)
fi

for name in "${commands[@]}"; do
  path="$BIN_DIR/$name"
  if [[ "$name" == "miclock" ]]; then
    if [[ -f "$path" && ! -L "$path" ]] &&
       /usr/bin/grep -qF "$WRAPPER_MARKER" "$path" 2>/dev/null; then
      /bin/rm -f "$path"
    fi
  elif [[ -L "$path" && "$(/usr/bin/readlink "$path")" == "miclock" ]]; then
    /bin/rm -f "$path"
  fi
done

# These are fixed, app-owned locations. Refuse symlinks before recursive removal.
for path in "$APP_PATH" "$SUPPORT_DIR" "$LEGACY_INSTALL_DIR" "$LEGACY_CONFIG_DIR"; do
  if [[ -L "$path" ]]; then
    /bin/echo "WARNING: refusing to recursively remove symlink: $path" >&2
    continue
  fi
  case "$path" in
    "$HOME/Applications/MicLock.app"|\
    "$HOME/Library/Application Support/MicLock"|\
    "$HOME/.local/libexec/mic-input-lock"|\
    "$HOME/.config/mic-input-lock") /bin/rm -rf "$path" ;;
    *) /bin/echo "ERROR: unsafe uninstall path: $path" >&2; exit 1 ;;
  esac
done

/bin/rm -f \
  "$HOME/Library/Logs/mic-input-lock.log" \
  "$HOME/Library/Logs/mic-input-lock.error.log" \
  "$HOME/Library/Logs/mic-input-lock-menu.log" \
  "$HOME/Library/Logs/mic-input-lock-menu.error.log"

/bin/echo "MicLock 已卸载，macOS 将恢复原本的默认输入选择行为。"
if [[ -t 0 && "${MICLOCK_NONINTERACTIVE:-0}" != "1" ]]; then
  /bin/echo -n "按回车键关闭此窗口…"
  read -r
fi
