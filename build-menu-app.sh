#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
readonly APP_SOURCE="$SOURCE_DIR/menu-app"
readonly SPARKLE_DIR="$SOURCE_DIR/vendor/Sparkle-2.10.0"
readonly OUTPUT_PATH="${1:-$SOURCE_DIR/build/MicLock.app}"

[[ "${OUTPUT_PATH:t}" == "MicLock.app" && ! -L "$OUTPUT_PATH" ]]
[[ "${OUTPUT_PATH:A:h}" != "/Applications" && "${OUTPUT_PATH:A:h}" != "$HOME/Applications" ]]
[[ -d "$SPARKLE_DIR/Sparkle.framework" ]]

build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mic-lock-app.XXXXXX")"
trap '/bin/rm -rf "$build_dir"' EXIT
stage_app="$build_dir/MicLock.app"
icon_png="$build_dir/MicLock-1024.png"
icon_sizes="$build_dir/icon-sizes"

/bin/mkdir -p \
  "$stage_app/Contents/MacOS" \
  "$stage_app/Contents/Resources" \
  "$icon_sizes" \
  "${OUTPUT_PATH:h}"

/usr/bin/xcrun clang \
  -fobjc-arc \
  -fblocks \
  -O2 \
  -Wall -Wextra -Wpedantic -Werror \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework Foundation \
  -framework CoreText \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework ServiceManagement \
  -F "$SPARKLE_DIR" -framework Sparkle \
  -Wl,-rpath,@executable_path/../Frameworks \
  "$APP_SOURCE/main.m" "$APP_SOURCE/MLAudio.m" "$APP_SOURCE/MLState.m" \
  "$APP_SOURCE/MLCorrectionPolicy.m" "$APP_SOURCE/MLGuide.m" \
  "$APP_SOURCE/MLStatusWindow.m" "$APP_SOURCE/MLUpdate.m" \
  "$APP_SOURCE/MLLifecycle.m" "$APP_SOURCE/MLFeedback.m" "$APP_SOURCE/MLAnalytics.m" \
  -o "$stage_app/Contents/MacOS/MicLock"

/usr/bin/xcrun clang \
  -fobjc-arc \
  -O2 \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 \
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
/usr/bin/install -m 644 "$APP_SOURCE/ReleaseNotes.txt" \
  "$stage_app/Contents/Resources/ReleaseNotes.txt"
/usr/bin/install -m 644 "$SPARKLE_DIR/LICENSE" \
  "$stage_app/Contents/Resources/Sparkle-LICENSE.txt"
/bin/mkdir -p "$stage_app/Contents/Frameworks"
/usr/bin/ditto --norsrc --noextattr "$SPARKLE_DIR/Sparkle.framework" \
  "$stage_app/Contents/Frameworks/Sparkle.framework"
for locale in en zh-Hans; do
  /bin/mkdir -p "$stage_app/Contents/Resources/$locale.lproj"
  /usr/bin/install -m 644 "$APP_SOURCE/$locale.lproj/Localizable.strings" \
    "$stage_app/Contents/Resources/$locale.lproj/Localizable.strings"
done

# A local build remains ad-hoc signed. Supplying a Developer ID identity enables
# hardened-runtime signing without changing the build recipe.
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  /usr/bin/codesign --force --sign - "$stage_app" >/dev/null
else
  framework="$stage_app/Contents/Frameworks/Sparkle.framework/Versions/B"
  for helper in "$framework"/XPCServices/*.xpc "$framework/Updater.app" "$framework/Autoupdate"; do
    [[ ! -e "$helper" ]] || /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$helper" >/dev/null
  done
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" \
    "$stage_app/Contents/Frameworks/Sparkle.framework" >/dev/null
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$stage_app" >/dev/null
fi
/usr/bin/codesign --verify --deep --strict "$stage_app"

/bin/rm -rf "$OUTPUT_PATH"
/bin/cp -R "$stage_app" "$OUTPUT_PATH"
/bin/echo "Built: $OUTPUT_PATH"
