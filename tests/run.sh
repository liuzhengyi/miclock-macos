#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h:h}"
readonly SPARKLE_DIR="$SOURCE_DIR/vendor/Sparkle-2.10.0"
build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/miclock-tests.XXXXXX")"
trap '/bin/rm -rf "$build_dir"' EXIT

/usr/bin/xcrun clang -fobjc-arc -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation \
  "$SOURCE_DIR/menu-app/generate_dmg_background.m" -o "$build_dir/generate-dmg-background"
"$build_dir/generate-dmg-background" "$build_dir/dmg-background.png"
/usr/bin/xcrun clang -fobjc-arc -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation \
  "$SOURCE_DIR/tests/test-dmg-background.m" -o "$build_dir/test-dmg-background"
"$build_dir/test-dmg-background" "$build_dir/dmg-background.png"

scripts=(
  "$SOURCE_DIR/scripts/fetch-sparkle.sh"
  "$SOURCE_DIR/build-menu-app.sh"
  "$SOURCE_DIR/build-dmg.sh"
  "$SOURCE_DIR/install.sh"
  "$SOURCE_DIR/uninstall.sh"
  "$SOURCE_DIR/miclock"
  "$SOURCE_DIR/distribution/install.command"
  "$SOURCE_DIR/distribution/uninstall.command"
)
for script in "${scripts[@]}"; do
  /bin/zsh -n "$script"
done
if /usr/bin/grep -R '/bin/readlink' "$SOURCE_DIR"/distribution/*.command |
   /usr/bin/grep -v '/usr/bin/readlink' >/dev/null; then
  /bin/echo "FAIL: macOS readlink is /usr/bin/readlink" >&2
  exit 1
fi

/usr/bin/plutil -lint \
  "$SOURCE_DIR/menu-app/Info.plist" \
  "$SOURCE_DIR/menu-app/en.lproj/Localizable.strings" \
  "$SOURCE_DIR/menu-app/zh-Hans.lproj/Localizable.strings" >/dev/null

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework Foundation -framework CoreAudio \
  -I "$SOURCE_DIR/menu-app" \
  "$SOURCE_DIR/tests/test-device-model.m" "$SOURCE_DIR/menu-app/MLAudio.m" \
  -o "$build_dir/test-device-model"
"$build_dir/test-device-model"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework Foundation \
  -I "$SOURCE_DIR/menu-app" \
  "$SOURCE_DIR/tests/test-correction-policy.m" "$SOURCE_DIR/menu-app/MLCorrectionPolicy.m" \
  -o "$build_dir/test-correction-policy"
"$build_dir/test-correction-policy"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework Foundation -framework CoreAudio \
  -I "$SOURCE_DIR/menu-app" \
  "$SOURCE_DIR/tests/test-state.m" "$SOURCE_DIR/menu-app/MLState.m" "$SOURCE_DIR/menu-app/MLAudio.m" \
  -o "$build_dir/test-state"
MICLOCK_SUPPORT_DIR="$build_dir/state" "$build_dir/test-state"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation \
  -framework CoreText -framework CoreAudio -framework AudioToolbox -framework ServiceManagement \
  -F "$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
  -I "$SOURCE_DIR/menu-app" \
  "$SOURCE_DIR/tests/test-enforcement.m" "$SOURCE_DIR/menu-app/MLAudio.m" \
  "$SOURCE_DIR/menu-app/MLState.m" "$SOURCE_DIR/menu-app/MLCorrectionPolicy.m" \
  "$SOURCE_DIR/menu-app/MLGuide.m" "$SOURCE_DIR/menu-app/MLStatusWindow.m" \
  "$SOURCE_DIR/menu-app/MLUpdate.m" "$SOURCE_DIR/menu-app/MLLifecycle.m" \
  "$SOURCE_DIR/menu-app/MLFeedback.m" "$SOURCE_DIR/menu-app/MLAnalytics.m" -o "$build_dir/test-enforcement"
MICLOCK_SUPPORT_DIR="$build_dir/coordinator-state" "$build_dir/test-enforcement"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation -framework ServiceManagement \
  -F "$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
  -I "$SOURCE_DIR/menu-app" "$SOURCE_DIR/tests/test-lifecycle.m" \
  "$SOURCE_DIR/menu-app/MLLifecycle.m" "$SOURCE_DIR/menu-app/MLUpdate.m" \
  -o "$build_dir/test-lifecycle"
MICLOCK_LIFECYCLE_TEST_DIR="$build_dir/lifecycle" "$build_dir/test-lifecycle"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation -framework CoreAudio -framework AudioToolbox \
  -I "$SOURCE_DIR/menu-app" "$SOURCE_DIR/tests/test-feedback.m" \
  "$SOURCE_DIR/menu-app/MLFeedback.m" "$SOURCE_DIR/menu-app/MLAnalytics.m" "$SOURCE_DIR/menu-app/MLAudio.m" "$SOURCE_DIR/menu-app/MLState.m" \
  -o "$build_dir/test-feedback"
MICLOCK_SUPPORT_DIR="$build_dir/feedback-state" "$build_dir/test-feedback"

/usr/bin/xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework Foundation -I "$SOURCE_DIR/menu-app" \
  "$SOURCE_DIR/tests/test-analytics.m" "$SOURCE_DIR/menu-app/MLAnalytics.m" -o "$build_dir/test-analytics"
"$build_dir/test-analytics"

"$SOURCE_DIR/build-menu-app.sh" "$build_dir/MicLock.app"
/usr/bin/codesign --verify --deep --strict "$build_dir/MicLock.app"
/usr/bin/file "$build_dir/MicLock.app/Contents/MacOS/MicLock" | /usr/bin/grep -q arm64
/usr/bin/file "$build_dir/MicLock.app/Contents/MacOS/MicLock" | /usr/bin/grep -q x86_64
[[ ! -e "$build_dir/MicLock.app/Contents/Resources/bin/SwitchAudioSource" ]]
[[ ! -d "$build_dir/MicLock.app/Contents/Library/LaunchAgents" ]]

MICLOCK_SUPPORT_DIR="$build_dir/cli-state" \
  "$build_dir/MicLock.app/Contents/MacOS/MicLock" --cli status >/dev/null
MICLOCK_SUPPORT_DIR="$build_dir/cli-state" \
  "$build_dir/MicLock.app/Contents/MacOS/MicLock" --cli diagnostics | /usr/bin/grep -q 'target:'
[[ ! -e "$build_dir/cli-state" ]]

/bin/echo "All MicLock tests passed."
