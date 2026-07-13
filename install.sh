#!/bin/zsh

set -euo pipefail

readonly LABEL="com.user.mic-input-lock"
readonly SOURCE_DIR="${0:A:h}"
readonly INSTALL_DIR="${MIC_INPUT_LOCK_INSTALL_DIR:-$HOME/.local/libexec/mic-input-lock}"
readonly CONFIG_DIR="${MIC_INPUT_LOCK_CONFIG_DIR:-$HOME/.config/mic-input-lock}"
readonly AGENTS_DIR="${MIC_INPUT_LOCK_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
readonly LOG_DIR="${MIC_INPUT_LOCK_LOG_DIR:-$HOME/Library/Logs}"
readonly PLIST_PATH="$AGENTS_DIR/$LABEL.plist"
readonly INSTALLED_SCRIPT="$INSTALL_DIR/mic-input-lock.sh"
readonly LAUNCHCTL="${LAUNCHCTL:-/bin/launchctl}"
readonly USER_ID="$(/usr/bin/id -u)"

requested_device=""
interval="2"
dry_run=0

usage() {
  /bin/cat <<'EOF'
Usage: ./install.sh [--device "device name"] [--interval seconds] [--dry-run]

Options:
  --device NAME       Select an exact input-device name without prompting.
  --interval SECONDS  Correction interval; default is 2 seconds.
  --dry-run           Detect and validate only; do not install or load anything.
  -h, --help          Show this help.
EOF
}

die() {
  /bin/echo "ERROR: $*" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --device)
      (( $# >= 2 )) || die "--device requires a value"
      requested_device="$2"
      shift 2
      ;;
    --interval)
      (( $# >= 2 )) || die "--interval requires a value"
      interval="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "$interval" =~ '^[1-9][0-9]*$' ]] || die "interval must be a positive integer"

mac_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if (( mac_major < 26 )); then
  /bin/echo "Note: this package was validated for macOS Tahoe 26; detected macOS $mac_major."
fi

switch_audio_source="${SWITCH_AUDIO_SOURCE:-}"
if [[ -z "$switch_audio_source" ]]; then
  switch_audio_source="$(command -v SwitchAudioSource 2>/dev/null || true)"
fi

if [[ -z "$switch_audio_source" || ! -x "$switch_audio_source" ]]; then
  brew_bin="$(command -v brew 2>/dev/null || true)"
  [[ -n "$brew_bin" ]] || die "Homebrew is required. Install it from https://brew.sh first."
  /bin/echo "Installing SwitchAudioSource with Homebrew..."
  "$brew_bin" install switchaudio-osx
  switch_audio_source="$(command -v SwitchAudioSource 2>/dev/null || true)"
fi
[[ -x "$switch_audio_source" ]] || die "SwitchAudioSource was not found after installation"
switch_audio_source="$(cd "${switch_audio_source:h}" && /bin/pwd -P)/${switch_audio_source:t}"

device_output="$($switch_audio_source -a -t input 2>/dev/null || true)"
devices=()
while IFS= read -r device; do
  [[ -n "$device" ]] && devices+=("$device")
done <<< "$device_output"

(( ${#devices[@]} > 0 )) || die "no CoreAudio input devices were visible. Run this installer from Terminal while logged into the Mac desktop."

selected_device=""
if [[ -n "$requested_device" ]]; then
  for device in "${devices[@]}"; do
    if [[ "$device" == "$requested_device" ]]; then
      selected_device="$device"
      break
    fi
  done
  [[ -n "$selected_device" ]] || die "input device not found: $requested_device"
else
  candidates=()
  for device in "${devices[@]}"; do
    normalized="${device:l}"
    case "$normalized" in
      *macbook*microphone*|*macbook*mic*|*macbook*麦克风*|*built-in*microphone*|*internal*microphone*|*内建*麦克风*)
        candidates+=("$device")
        ;;
    esac
  done

  if (( ${#candidates[@]} == 1 )); then
    selected_device="${candidates[1]}"
  elif [[ -t 0 ]]; then
    /bin/echo "Available input devices:"
    index=1
    for device in "${devices[@]}"; do
      /bin/echo "  $index) $device"
      (( index++ ))
    done
    /bin/echo -n "Choose the built-in MacBook Air microphone [1-${#devices[@]}]: "
    read -r choice
    [[ "$choice" =~ '^[0-9]+$' ]] || die "selection must be a number"
    (( choice >= 1 && choice <= ${#devices[@]} )) || die "selection is out of range"
    selected_device="${devices[$choice]}"
  else
    /bin/echo "Available input devices:" >&2
    for device in "${devices[@]}"; do /bin/echo "  $device" >&2; done
    die "built-in microphone was ambiguous; rerun with --device and an exact name"
  fi
fi

/bin/echo "Selected input: $selected_device"
/bin/echo "Correction interval: ${interval}s"

if (( dry_run )); then
  /bin/echo "Dry run complete; nothing was installed."
  exit 0
fi

/bin/mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$AGENTS_DIR" "$LOG_DIR"
/usr/bin/install -m 755 "$SOURCE_DIR/mic-input-lock.sh" "$INSTALLED_SCRIPT"
/bin/echo "$selected_device" > "$CONFIG_DIR/device-name"
/bin/echo "$interval" > "$CONFIG_DIR/check-interval"
/bin/chmod 600 "$CONFIG_DIR/device-name" "$CONFIG_DIR/check-interval"

temp_plist="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mic-input-lock.XXXXXX.plist")"
trap '/bin/rm -f "$temp_plist"' EXIT
/bin/cp "$SOURCE_DIR/com.user.mic-input-lock.plist.template" "$temp_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$INSTALLED_SCRIPT" "$temp_plist"
/usr/bin/plutil -replace EnvironmentVariables.HOME -string "$HOME" "$temp_plist"
/usr/bin/plutil -replace EnvironmentVariables.SWITCH_AUDIO_SOURCE -string "$switch_audio_source" "$temp_plist"
/usr/bin/plutil -replace StandardOutPath -string "$LOG_DIR/mic-input-lock.log" "$temp_plist"
/usr/bin/plutil -replace StandardErrorPath -string "$LOG_DIR/mic-input-lock.error.log" "$temp_plist"
/usr/bin/plutil -lint "$temp_plist" >/dev/null
/usr/bin/install -m 644 "$temp_plist" "$PLIST_PATH"

# Apply once before loading, then register a persistent per-user LaunchAgent.
SWITCH_AUDIO_SOURCE="$switch_audio_source" \
MIC_INPUT_LOCK_CONFIG_DIR="$CONFIG_DIR" \
  "$INSTALLED_SCRIPT" --once

"$LAUNCHCTL" bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
"$LAUNCHCTL" bootstrap "gui/$USER_ID" "$PLIST_PATH"
"$LAUNCHCTL" enable "gui/$USER_ID/$LABEL"
"$LAUNCHCTL" kickstart -k "gui/$USER_ID/$LABEL"

/bin/sleep 1
current="$($switch_audio_source -c -t input 2>/dev/null || true)"
if [[ "$current" == "$selected_device" ]]; then
  /bin/echo "Installed and active. Current default input: $current"
else
  /bin/echo "Installed, but verification returned: ${current:-<unknown>}" >&2
  /bin/echo "Check: $LOG_DIR/mic-input-lock.error.log" >&2
  exit 1
fi
