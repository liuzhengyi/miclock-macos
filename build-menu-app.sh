#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
readonly APP_SOURCE="$SOURCE_DIR/menu-app"
readonly OUTPUT_PATH="${1:-$SOURCE_DIR/build/MicLock.app}"

switch_source="${SWITCH_AUDIO_SOURCE_BUNDLE_SOURCE:-}"
if [[ -z "$switch_source" ]]; then
  for candidate in \
    /opt/homebrew/opt/switchaudio-osx/SwitchAudioSource \
    /opt/homebrew/Cellar/switchaudio-osx/1.2.2/SwitchAudioSource; do
    if [[ -x "$candidate" ]]; then
      switch_source="$candidate"
      break
    fi
  done
fi
[[ -x "$switch_source" ]] || {
  /bin/echo "ERROR: the real SwitchAudioSource Mach-O binary was not found" >&2
  exit 1
}
if /usr/bin/file "$switch_source" | /usr/bin/grep -q "shell script"; then
  /bin/echo "ERROR: refusing to bundle the Homebrew wrapper script: $switch_source" >&2
  exit 1
fi

license_source="${SWITCH_AUDIO_SOURCE_LICENSE_SOURCE:-${switch_source:h}/license.txt}"
[[ -r "$license_source" ]] || {
  /bin/echo "ERROR: SwitchAudioSource MIT license was not found" >&2
  exit 1
}

build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mic-lock-app.XXXXXX")"
trap '/bin/rm -rf "$build_dir"' EXIT
stage_app="$build_dir/MicLock.app"
icon_png="$build_dir/MicLock-1024.png"
icon_sizes="$build_dir/icon-sizes"

/bin/mkdir -p \
  "$stage_app/Contents/MacOS" \
  "$stage_app/Contents/Resources/bin" \
  "$stage_app/Contents/Resources/ThirdPartyNotices" \
  "$stage_app/Contents/Resources/InstallerSupport" \
  "$icon_sizes" \
  "${OUTPUT_PATH:h}"

/usr/bin/xcrun clang \
  -fobjc-arc \
  -O2 \
  -mmacosx-version-min=26.0 \
  -framework AppKit \
  -framework Foundation \
  "$APP_SOURCE/main.m" \
  -o "$stage_app/Contents/MacOS/MicLockMenu"

/usr/bin/xcrun clang \
  -fobjc-arc \
  -O2 \
  -mmacosx-version-min=26.0 \
  -framework AppKit \
  -framework Foundation \
  "$APP_SOURCE/generate_app_icon.m" \
  -o "$build_dir/generate_app_icon"
"$build_dir/generate_app_icon" "$icon_png"

for size in 16 32 64 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$icon_png" --out "$icon_sizes/$size.png" >/dev/null
done
/bin/cp "$icon_png" "$icon_sizes/1024.png"
/usr/bin/xcrun clang -O2 "$APP_SOURCE/create_icns.c" -o "$build_dir/create_icns"
"$build_dir/create_icns" \
  "$stage_app/Contents/Resources/MicLock.icns" \
  "$icon_sizes/16.png" \
  "$icon_sizes/32.png" \
  "$icon_sizes/64.png" \
  "$icon_sizes/128.png" \
  "$icon_sizes/256.png" \
  "$icon_sizes/512.png" \
  "$icon_sizes/1024.png"

/usr/bin/install -m 644 "$APP_SOURCE/Info.plist" "$stage_app/Contents/Info.plist"
/usr/bin/install -m 644 "$SOURCE_DIR/LICENSE" \
  "$stage_app/Contents/Resources/MicLock-LICENSE.txt"
/usr/bin/install -m 755 "$switch_source" "$stage_app/Contents/Resources/bin/SwitchAudioSource"
/usr/bin/install -m 644 "$license_source" \
  "$stage_app/Contents/Resources/ThirdPartyNotices/SwitchAudioSource-LICENSE.txt"
/usr/bin/install -m 755 "$SOURCE_DIR/mic-input-lock.sh" \
  "$stage_app/Contents/Resources/InstallerSupport/mic-input-lock.sh"
/usr/bin/install -m 755 "$SOURCE_DIR/miclock" \
  "$stage_app/Contents/Resources/InstallerSupport/miclock"
/usr/bin/install -m 644 "$SOURCE_DIR/com.user.mic-input-lock.plist.template" \
  "$stage_app/Contents/Resources/InstallerSupport/com.user.mic-input-lock.plist.template"
/usr/bin/install -m 644 "$APP_SOURCE/com.user.mic-input-lock-menu.plist.template" \
  "$stage_app/Contents/Resources/InstallerSupport/com.user.mic-input-lock-menu.plist.template"

# Sign inner code first, then seal the outer app. With no Developer ID available,
# this produces an ad-hoc signed testing build; SIGNING_IDENTITY can override it.
identity="${SIGNING_IDENTITY:--}"
/usr/bin/codesign --force --sign "$identity" \
  "$stage_app/Contents/Resources/bin/SwitchAudioSource" >/dev/null
/usr/bin/codesign --force --sign "$identity" "$stage_app" >/dev/null
/usr/bin/codesign --verify --deep --strict "$stage_app"

/bin/rm -rf "$OUTPUT_PATH"
/bin/cp -R "$stage_app" "$OUTPUT_PATH"
/bin/echo "Built: $OUTPUT_PATH"
