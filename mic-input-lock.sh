#!/bin/zsh

# Keep the macOS global default input on a configured microphone.
# This script is installed and supervised by launchd; it does not need root.

set -u

readonly CONFIG_DIR="${MIC_INPUT_LOCK_CONFIG_DIR:-$HOME/.config/mic-input-lock}"
readonly DEVICE_FILE="$CONFIG_DIR/device-name"
readonly INTERVAL_FILE="$CONFIG_DIR/check-interval"
readonly ONCE="${1:-}"

log() {
  /bin/echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*"
}

find_switch_audio_source() {
  local candidate

  if [[ -n "${SWITCH_AUDIO_SOURCE:-}" && -x "$SWITCH_AUDIO_SOURCE" ]]; then
    /bin/echo "$SWITCH_AUDIO_SOURCE"
    return 0
  fi

  for candidate in \
    "$HOME/Applications/MicLock.app/Contents/Resources/bin/SwitchAudioSource" \
    /Applications/MicLock.app/Contents/Resources/bin/SwitchAudioSource \
    /opt/homebrew/opt/switchaudio-osx/SwitchAudioSource \
    /opt/homebrew/bin/SwitchAudioSource \
    /usr/local/bin/SwitchAudioSource; do
    if [[ -x "$candidate" ]]; then
      /bin/echo "$candidate"
      return 0
    fi
  done

  return 1
}

if [[ ! -r "$DEVICE_FILE" ]]; then
  log "ERROR: missing device configuration: $DEVICE_FILE"
  exit 78
fi

target_device="$(/usr/bin/head -n 1 "$DEVICE_FILE")"
if [[ -z "$target_device" ]]; then
  log "ERROR: configured input device is empty"
  exit 78
fi

interval="2"
if [[ -r "$INTERVAL_FILE" ]]; then
  interval="$(/usr/bin/head -n 1 "$INTERVAL_FILE")"
fi
if [[ ! "$interval" =~ '^[1-9][0-9]*$' ]]; then
  log "ERROR: check interval must be a positive integer, got: $interval"
  exit 78
fi

switch_audio_source="$(find_switch_audio_source)" || {
  log "ERROR: SwitchAudioSource is not installed"
  exit 69
}

last_error_time=0

enforce_input() {
  local current after now

  current="$($switch_audio_source -c -t input 2>/dev/null || true)"
  if [[ "$current" == "$target_device" ]]; then
    return 0
  fi

  if "$switch_audio_source" -t input -s "$target_device" >/dev/null 2>&1; then
    after="$($switch_audio_source -c -t input 2>/dev/null || true)"
    if [[ "$after" == "$target_device" ]]; then
      log "default input changed: ${current:-<unknown>} -> $target_device"
      return 0
    fi
  fi

  # Avoid filling the log if CoreAudio is temporarily unavailable during wake.
  now="$(/bin/date +%s)"
  if (( now - last_error_time >= 60 )); then
    log "WARNING: could not select '$target_device'; CoreAudio may be unavailable"
    last_error_time="$now"
  fi
  return 1
}

if [[ "$ONCE" == "--once" ]]; then
  enforce_input
  exit $?
fi

log "started; enforcing input '$target_device' every ${interval}s"
while true; do
  enforce_input || true
  /bin/sleep "$interval"
done
