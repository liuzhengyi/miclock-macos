#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SOURCE_APP="$SCRIPT_DIR/MicLock.app"
readonly APP_ROOT="$HOME/Applications"
readonly APP_PATH="$APP_ROOT/MicLock.app"
readonly APP_BINARY="$APP_PATH/Contents/MacOS/MicLock"
readonly BIN_DIR="$HOME/.local/bin"
readonly SUPPORT_DIR="$HOME/Library/Application Support/MicLock"
readonly MANIFEST="$SUPPORT_DIR/managed-commands.txt"
readonly USER_ID="$(/usr/bin/id -u)"
readonly LEGACY_LOCK_PLIST="$HOME/Library/LaunchAgents/com.user.mic-input-lock.plist"
readonly LEGACY_MENU_PLIST="$HOME/Library/LaunchAgents/com.user.mic-input-lock-menu.plist"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
readonly WRAPPER_MARKER="# Managed by MicLock io.github.liuzhengyi.miclock"

stage_app=""
backup_app=""
backup_cli=""
backup_manifest=""
backup_legacy_lock=""
backup_legacy_menu=""
created_aliases=()
installed_app=0
previous_login_enabled=0
previous_lock_enabled=0

finish() {
  local result_code="$1"
  trap - EXIT
  if (( result_code != 0 )); then
    /bin/echo "MicLock 安装失败，正在恢复原版本…" >&2
    if (( installed_app )); then
      /bin/rm -rf "$APP_PATH"
      [[ -n "$backup_app" && -d "$backup_app" ]] && /bin/mv "$backup_app" "$APP_PATH"
    fi
    if (( previous_login_enabled )) && [[ -x "$APP_BINARY" ]]; then
      "$APP_BINARY" --cli login-on >/dev/null 2>&1 || true
    fi
    if [[ -n "$backup_cli" && -f "$backup_cli" ]]; then
      /bin/mv -f "$backup_cli" "$BIN_DIR/miclock"
    fi
    for alias_path in "${created_aliases[@]}"; do
      [[ -L "$alias_path" && "$(/usr/bin/readlink "$alias_path")" == "miclock" ]] && /bin/rm -f "$alias_path"
    done
    if [[ -n "$backup_manifest" && -f "$backup_manifest" ]]; then
      /bin/mv -f "$backup_manifest" "$MANIFEST"
    fi
    if [[ -n "$backup_legacy_lock" && -f "$backup_legacy_lock" ]]; then
      /usr/bin/install -m 644 "$backup_legacy_lock" "$LEGACY_LOCK_PLIST"
      /bin/launchctl bootstrap "gui/$USER_ID" "$LEGACY_LOCK_PLIST" 2>/dev/null || true
    fi
    if [[ -n "$backup_legacy_menu" && -f "$backup_legacy_menu" ]]; then
      /usr/bin/install -m 644 "$backup_legacy_menu" "$LEGACY_MENU_PLIST"
      /bin/launchctl bootstrap "gui/$USER_ID" "$LEGACY_MENU_PLIST" 2>/dev/null || true
    fi
  fi
  [[ -n "$stage_app" && -d "$stage_app" ]] && /bin/rm -rf "$stage_app"
  [[ -n "$backup_app" && -d "$backup_app" ]] && /bin/rm -rf "$backup_app"
  [[ -n "$backup_cli" && -f "$backup_cli" ]] && /bin/rm -f "$backup_cli"
  [[ -n "$backup_manifest" && -f "$backup_manifest" ]] && /bin/rm -f "$backup_manifest"
  [[ -n "$backup_legacy_lock" && -f "$backup_legacy_lock" ]] && /bin/rm -f "$backup_legacy_lock"
  [[ -n "$backup_legacy_menu" && -f "$backup_legacy_menu" ]] && /bin/rm -f "$backup_legacy_menu"
  /bin/echo
  if (( result_code == 0 )); then
    /bin/echo "安装完成。可以通过 Spotlight 搜索 MicLock，或在终端运行 miclock。"
  else
    /bin/echo "安装未完成；原有版本已尽可能恢复。请保留此窗口中的错误信息。" >&2
  fi
  if [[ -t 0 && "${MICLOCK_NONINTERACTIVE:-0}" != "1" ]]; then
    /bin/echo -n "按回车键关闭此窗口…"
    read -r
  fi
  exit "$result_code"
}
trap 'finish $?' EXIT

[[ -d "$SOURCE_APP" ]] || {
  /bin/echo "ERROR: MicLock.app 必须和安装脚本放在同一个磁盘映像中" >&2
  false
}
[[ "$(/usr/bin/id -u)" != "0" ]] || {
  /bin/echo "ERROR: 请不要使用 sudo 或 root 安装 MicLock" >&2
  false
}

# Validate the complete replacement before stopping or removing anything.
/usr/bin/plutil -lint "$SOURCE_APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
[[ -x "$SOURCE_APP/Contents/MacOS/MicLock" ]] || {
  /bin/echo "ERROR: 安装包中缺少 MicLock 可执行文件" >&2
  false
}

if [[ -e "$BIN_DIR/miclock" && ! -L "$BIN_DIR/miclock" ]]; then
  if ! /usr/bin/grep -qF "$WRAPPER_MARKER" "$BIN_DIR/miclock" 2>/dev/null &&
     ! /usr/bin/grep -qF 'com.user.mic-input-lock' "$BIN_DIR/miclock" 2>/dev/null; then
    /bin/echo "ERROR: $BIN_DIR/miclock 已被其他程序占用，未进行覆盖" >&2
    false
  fi
fi

/bin/mkdir -p "$APP_ROOT" "$BIN_DIR" "$SUPPORT_DIR"
/bin/chmod 700 "$SUPPORT_DIR"
stage_app="$APP_ROOT/.MicLock.stage.$$.app"
/usr/bin/ditto "$SOURCE_APP" "$stage_app"
/usr/bin/codesign --verify --deep --strict "$stage_app"
/usr/bin/plutil -lint "$stage_app/Contents/Info.plist" >/dev/null

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$stage_app/Contents/Info.plist")"
/bin/echo "正在安装 MicLock $version…"

# Stop and remove the legacy polling agents only after the replacement passed validation.
if [[ -f "$LEGACY_LOCK_PLIST" ]]; then
  backup_legacy_lock="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-legacy-lock.XXXXXX")"
  /bin/cp "$LEGACY_LOCK_PLIST" "$backup_legacy_lock"
fi
if [[ -f "$LEGACY_MENU_PLIST" ]]; then
  backup_legacy_menu="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-legacy-menu.XXXXXX")"
  /bin/cp "$LEGACY_MENU_PLIST" "$backup_legacy_menu"
fi
/bin/launchctl bootout "gui/$USER_ID" "$LEGACY_LOCK_PLIST" 2>/dev/null || true
/bin/launchctl bootout "gui/$USER_ID" "$LEGACY_MENU_PLIST" 2>/dev/null || true
/bin/rm -f "$LEGACY_LOCK_PLIST" "$LEGACY_MENU_PLIST"
if [[ -x "$APP_BINARY" ]]; then
  if [[ -f "$SUPPORT_DIR/config.plist" &&
        "$(/usr/bin/plutil -extract enabled raw "$SUPPORT_DIR/config.plist" 2>/dev/null)" == "true" ]]; then
    previous_lock_enabled=1
  fi
  "$APP_BINARY" --cli login-status >/dev/null 2>&1 && previous_login_enabled=1 || true
  "$APP_BINARY" --cli login-off >/dev/null 2>&1 || true
  "$APP_BINARY" --cli quit >/dev/null 2>&1 || true
fi

installed_app=1
if [[ -d "$APP_PATH" ]]; then
  backup_app="$APP_ROOT/.MicLock.backup.$$.app"
  /bin/mv "$APP_PATH" "$backup_app"
fi
/bin/mv "$stage_app" "$APP_PATH"
stage_app=""

if [[ -f "$BIN_DIR/miclock" && ! -L "$BIN_DIR/miclock" ]]; then
  backup_cli="${TMPDIR:-/tmp}/miclock-cli.$$.backup"
  /bin/mv "$BIN_DIR/miclock" "$backup_cli"
fi
if [[ -f "$MANIFEST" ]]; then
  backup_manifest="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-manifest.XXXXXX")"
  /bin/cp "$MANIFEST" "$backup_manifest"
fi

wrapper_temp="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-wrapper.XXXXXX")"
{
  /usr/bin/printf '%s\n' '#!/bin/zsh'
  /usr/bin/printf '%s\n' "$WRAPPER_MARKER"
  /usr/bin/printf '%s\n' 'readonly app="$HOME/Applications/MicLock.app/Contents/MacOS/MicLock"'
  /usr/bin/printf '%s\n' '[[ -x "$app" ]] || { print -u2 "MicLock is not installed: $app"; exit 127; }'
  /usr/bin/printf '%s\n' 'exec "$app" --cli "${0:t}" "$@"'
} > "$wrapper_temp"
/bin/chmod 755 "$wrapper_temp"
/bin/mv -f "$wrapper_temp" "$BIN_DIR/miclock"

managed_commands=(miclock)
for name in mic-on mic-off mic-status mic-list mic-fix mic-pick mic-set mic-quit mic-start; do
  path="$BIN_DIR/$name"
  existed=0
  if [[ -e "$path" || -L "$path" ]]; then
    existed=1
    if [[ -L "$path" && "$(/usr/bin/readlink "$path")" == "miclock" ]]; then
      /bin/rm -f "$path"
    else
      /bin/echo "WARNING: 未覆盖已有命令 $path" >&2
      continue
    fi
  fi
  /bin/ln -s miclock "$path"
  (( existed )) || created_aliases+=("$path")
  managed_commands+=("$name")
done
/usr/bin/printf '%s\n' "${managed_commands[@]}" > "$MANIFEST"
/bin/chmod 600 "$MANIFEST"

# Initialize a new target without replacing a saved UID or enabling a new
# installation. Existing enabled/login preferences are restored on upgrade.
"$APP_BINARY" --cli init-configuration >/dev/null 2>&1 || true
if (( previous_lock_enabled )) && ! "$APP_BINARY" --cli on; then
  /bin/echo "WARNING: 未能恢复原有锁定，请打开 MicLock 后检查目标设备。" >&2
fi
if (( previous_login_enabled )) && ! "$APP_BINARY" --cli login-on >/dev/null 2>&1; then
  /bin/echo "WARNING: 无法自动注册登录启动；可在 MicLock 菜单中稍后开启。" >&2
fi
"$LSREGISTER" -f "$APP_PATH"
/usr/bin/open -g "$APP_PATH" 2>/dev/null || \
  /bin/echo "WARNING: macOS 阻止了首次启动，请按住 Control 点击 MicLock.app 并选择打开。" >&2

/bin/sleep 1
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
[[ -x "$APP_BINARY" ]]

installed_app=0
/bin/rm -rf "$backup_app" 2>/dev/null || true
backup_app=""
/bin/rm -f "$backup_cli" 2>/dev/null || true
backup_cli=""
/bin/rm -f "$backup_manifest" "$backup_legacy_lock" "$backup_legacy_menu" 2>/dev/null || true
backup_manifest=""
backup_legacy_lock=""
backup_legacy_menu=""
if [[ -f "$SUPPORT_DIR/config.plist" ]]; then
  /bin/rm -rf "$HOME/.local/libexec/mic-input-lock" "$HOME/.config/mic-input-lock"
fi
exit 0
