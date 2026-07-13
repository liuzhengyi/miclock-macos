#!/bin/zsh

set -euo pipefail

readonly LOCK_LABEL="com.user.mic-input-lock"
readonly MENU_LABEL="com.user.mic-input-lock-menu"
readonly SCRIPT_DIR="${0:A:h}"
readonly SOURCE_APP="$SCRIPT_DIR/MicLock.app"
readonly APP_PATH="$HOME/Applications/MicLock.app"
readonly SUPPORT="$APP_PATH/Contents/Resources/InstallerSupport"
readonly SWITCH_AUDIO="$APP_PATH/Contents/Resources/bin/SwitchAudioSource"
readonly INSTALL_DIR="$HOME/.local/libexec/mic-input-lock"
readonly CONFIG_DIR="$HOME/.config/mic-input-lock"
readonly BIN_DIR="$HOME/.local/bin"
readonly AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly LOG_DIR="$HOME/Library/Logs"
readonly LOCK_PLIST="$AGENTS_DIR/$LOCK_LABEL.plist"
readonly MENU_PLIST="$AGENTS_DIR/$MENU_LABEL.plist"
readonly USER_ID="$(/usr/bin/id -u)"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

finish() {
  local result_code="$1"
  /bin/echo
  if (( result_code == 0 )); then
    /bin/echo "安装完成。可以通过 Spotlight 搜索 MicLock。"
  else
    /bin/echo "安装失败，请保留此窗口中的错误信息。" >&2
  fi
  if [[ -t 0 ]]; then
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

/bin/echo "正在安装 MicLock 2.1.1…"
/bin/launchctl bootout "gui/$USER_ID" "$MENU_PLIST" 2>/dev/null || true
/bin/launchctl bootout "gui/$USER_ID" "$LOCK_PLIST" 2>/dev/null || true

/bin/mkdir -p "$HOME/Applications" "$INSTALL_DIR" "$CONFIG_DIR" "$BIN_DIR" "$AGENTS_DIR" "$LOG_DIR"
/bin/rm -rf "$APP_PATH"
/usr/bin/ditto "$SOURCE_APP" "$APP_PATH"

[[ -x "$SWITCH_AUDIO" ]] || {
  /bin/echo "ERROR: 分发包缺少 SwitchAudioSource" >&2
  false
}

/usr/bin/install -m 755 "$SUPPORT/mic-input-lock.sh" "$INSTALL_DIR/mic-input-lock.sh"
/usr/bin/install -m 755 "$SUPPORT/miclock" "$BIN_DIR/miclock"
for name in mic-on mic-off mic-status mic-list mic-fix mic-pick mic-set mic-quit mic-start; do
  /bin/ln -sf miclock "$BIN_DIR/$name"
done

device_output="$("$SWITCH_AUDIO" -a -t input 2>/dev/null || true)"
devices=()
while IFS= read -r device; do
  [[ -n "$device" ]] && devices+=("$device")
done <<< "$device_output"
(( ${#devices[@]} > 0 )) || {
  /bin/echo "ERROR: 当前用户会话没有可见的 CoreAudio 输入设备" >&2
  false
}

target=""
if [[ -r "$CONFIG_DIR/device-name" ]]; then
  previous="$(/usr/bin/head -n 1 "$CONFIG_DIR/device-name")"
  for device in "${devices[@]}"; do
    [[ "$device" == "$previous" ]] && target="$device"
  done
fi
if [[ -z "$target" ]]; then
  for device in "${devices[@]}"; do
    normalized="${device:l}"
    case "$normalized" in
      *macbook*microphone*|*macbook*mic*|*macbook*麦克风*|*built-in*microphone*|*internal*microphone*|*内建*麦克风*)
        target="$device"
        break
        ;;
    esac
  done
fi
if [[ -z "$target" ]]; then
  current="$("$SWITCH_AUDIO" -c -t input 2>/dev/null || true)"
  target="${current:-${devices[1]}}"
fi

/bin/echo "$target" > "$CONFIG_DIR/device-name"
/bin/echo "2" > "$CONFIG_DIR/check-interval"
/bin/chmod 600 "$CONFIG_DIR/device-name" "$CONFIG_DIR/check-interval"

lock_temp="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-lock.XXXXXX.plist")"
menu_temp="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/miclock-menu.XXXXXX.plist")"
/bin/cp "$SUPPORT/com.user.mic-input-lock.plist.template" "$lock_temp"
/usr/bin/plutil -insert ProgramArguments.0 -string "$INSTALL_DIR/mic-input-lock.sh" "$lock_temp"
/usr/bin/plutil -replace EnvironmentVariables.HOME -string "$HOME" "$lock_temp"
/usr/bin/plutil -replace EnvironmentVariables.SWITCH_AUDIO_SOURCE -string "$SWITCH_AUDIO" "$lock_temp"
/usr/bin/plutil -replace StandardOutPath -string "$LOG_DIR/mic-input-lock.log" "$lock_temp"
/usr/bin/plutil -replace StandardErrorPath -string "$LOG_DIR/mic-input-lock.error.log" "$lock_temp"
/usr/bin/plutil -lint "$lock_temp" >/dev/null
/usr/bin/install -m 644 "$lock_temp" "$LOCK_PLIST"

/bin/cp "$SUPPORT/com.user.mic-input-lock-menu.plist.template" "$menu_temp"
/usr/bin/plutil -insert ProgramArguments.0 -string "$APP_PATH/Contents/MacOS/MicLockMenu" "$menu_temp"
/usr/bin/plutil -replace StandardOutPath -string "$LOG_DIR/mic-input-lock-menu.log" "$menu_temp"
/usr/bin/plutil -replace StandardErrorPath -string "$LOG_DIR/mic-input-lock-menu.error.log" "$menu_temp"
/usr/bin/plutil -lint "$menu_temp" >/dev/null
/usr/bin/install -m 644 "$menu_temp" "$MENU_PLIST"
/bin/rm -f "$lock_temp" "$menu_temp"

"$LSREGISTER" -f "$APP_PATH"
/bin/launchctl enable "gui/$USER_ID/$LOCK_LABEL"
/bin/launchctl enable "gui/$USER_ID/$MENU_LABEL"
SWITCH_AUDIO_SOURCE="$SWITCH_AUDIO" MIC_INPUT_LOCK_CONFIG_DIR="$CONFIG_DIR" \
  "$INSTALL_DIR/mic-input-lock.sh" --once
/bin/launchctl bootstrap "gui/$USER_ID" "$LOCK_PLIST"
/bin/launchctl bootstrap "gui/$USER_ID" "$MENU_PLIST"
/bin/launchctl kickstart -k "gui/$USER_ID/$MENU_LABEL"
/usr/bin/open -g "$APP_PATH" 2>/dev/null || true

/bin/sleep 1
/bin/launchctl print "gui/$USER_ID/$LOCK_LABEL" >/dev/null
/bin/launchctl print "gui/$USER_ID/$MENU_LABEL" >/dev/null
trap - EXIT
finish 0
