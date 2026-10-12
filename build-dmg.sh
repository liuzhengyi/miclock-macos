#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
readonly VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$SOURCE_DIR/menu-app/Info.plist")"
readonly OUTPUT_PATH="${1:-$SOURCE_DIR/release/MicLock-${VERSION}.dmg}"
readonly LAYOUT_PYTHON="${MICLOCK_LAYOUT_PYTHON:-python3}"
readonly LAYOUT_MODULES="${MICLOCK_LAYOUT_MODULES:-}"
readonly PREBUILT_APP="${MICLOCK_PREBUILT_APP:-}"

[[ "${OUTPUT_PATH:t}" == "MicLock-${VERSION}.dmg" && ! -L "$OUTPUT_PATH" ]]
if [[ -n "$PREBUILT_APP" ]]; then
  # Preserve the exact app that passed device/UI acceptance. Never rebuild or
  # re-sign it here: changing its bytes would invalidate that acceptance.
  [[ -d "$PREBUILT_APP" && ! -L "$PREBUILT_APP" && "${PREBUILT_APP:t}" == "MicLock.app" ]] || {
    /bin/echo "MICLOCK_PREBUILT_APP must name a real MicLock.app directory." >&2
    exit 1
  }
  [[ -f "$PREBUILT_APP/Contents/MacOS/MicLock" && ! -L "$PREBUILT_APP/Contents/MacOS/MicLock" ]]
  /usr/bin/plutil -lint "$PREBUILT_APP/Contents/Info.plist" >/dev/null
  # Compare the complete plist, including update keys and privacy defaults,
  # rather than only the user-visible version string.
  if ! /usr/bin/cmp -s \
    <(/usr/bin/plutil -convert xml1 -o - "$SOURCE_DIR/menu-app/Info.plist") \
    <(/usr/bin/plutil -convert xml1 -o - "$PREBUILT_APP/Contents/Info.plist"); then
    /bin/echo "Prebuilt app Info.plist differs from the current release source." >&2
    exit 1
  fi
  /usr/bin/codesign --verify --deep --strict "$PREBUILT_APP"
  prebuilt_checksum="$(/usr/bin/shasum -a 256 "$PREBUILT_APP/Contents/MacOS/MicLock" | /usr/bin/awk '{print $1}')"
  if [[ -n "${MICLOCK_PREBUILT_BINARY_SHA256:-}" && "$prebuilt_checksum" != "$MICLOCK_PREBUILT_BINARY_SHA256" ]]; then
    /bin/echo "Prebuilt executable differs from the accepted SHA-256." >&2
    exit 1
  fi
elif [[ -n "${MICLOCK_PREBUILT_BINARY_SHA256:-}" ]]; then
  /bin/echo "MICLOCK_PREBUILT_BINARY_SHA256 requires MICLOCK_PREBUILT_APP." >&2
  exit 1
fi
PYTHONPATH="$LAYOUT_MODULES" "$LAYOUT_PYTHON" -c 'import ds_store, mac_alias' >/dev/null 2>&1 || {
  /bin/echo "Install build-only ds_store==1.3.2 and mac_alias==2.2.3 in MICLOCK_LAYOUT_PYTHON venv, or set MICLOCK_LAYOUT_MODULES." >&2
  exit 1
}
build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/miclock-dmg.XXXXXX")"
mountpoint="$build_dir/mounted"
cleanup() {
  if /sbin/mount | /usr/bin/grep -F " on $mountpoint " >/dev/null; then
    /usr/bin/hdiutil detach "$mountpoint" >/dev/null || true
  fi
  /bin/rm -rf "$build_dir"
}
trap cleanup EXIT
stage="$build_dir/stage"
/bin/mkdir -p "$stage/.background" "$mountpoint" "${OUTPUT_PATH:h}"

if [[ -n "$PREBUILT_APP" ]]; then
  /usr/bin/ditto "$PREBUILT_APP" "$stage/MicLock.app"
  /usr/bin/codesign --verify --deep --strict "$stage/MicLock.app"
  staged_checksum="$(/usr/bin/shasum -a 256 "$stage/MicLock.app/Contents/MacOS/MicLock" | /usr/bin/awk '{print $1}')"
  [[ "$staged_checksum" == "$prebuilt_checksum" ]] || {
    /bin/echo "Staged executable does not match the prebuilt app." >&2
    exit 1
  }
else
  "$SOURCE_DIR/build-menu-app.sh" "$stage/MicLock.app"
fi
/bin/ln -s /Applications "$stage/Applications"
/usr/bin/xcrun clang -fobjc-arc -Wall -Wextra -Wpedantic -Werror \
  -mmacosx-version-min=13.0 -framework AppKit -framework Foundation \
  "$SOURCE_DIR/menu-app/generate_dmg_background.m" -o "$build_dir/generate-dmg-background"
"$build_dir/generate-dmg-background" "$stage/.background/install.png"

# The image root contains the app and Applications alias, not an extra folder
# or install/uninstall command files. Write Finder's layout on the mounted HFS+
# volume so its background alias refers to the actual image rather than staging.
/usr/bin/hdiutil create -volname "MicLock $VERSION" -fs HFS+ \
  -srcfolder "$stage" -ov -format UDRW "$build_dir/writable.dmg" >/dev/null
/usr/bin/hdiutil attach "$build_dir/writable.dmg" -readwrite -noverify -nobrowse \
  -mountpoint "$mountpoint" >/dev/null
PYTHONPATH="$LAYOUT_MODULES" "$LAYOUT_PYTHON" "$SOURCE_DIR/distribution/生成安装布局.py" "$mountpoint"
/usr/bin/hdiutil detach "$mountpoint" >/dev/null
/usr/bin/hdiutil convert "$build_dir/writable.dmg" -format UDZO -ov -o "$OUTPUT_PATH" >/dev/null
identity="${SIGNING_IDENTITY:--}"
/usr/bin/codesign --force --sign "$identity" "$OUTPUT_PATH" >/dev/null
/usr/bin/hdiutil verify "$OUTPUT_PATH" >/dev/null
checksum="$(/usr/bin/shasum -a 256 "$OUTPUT_PATH" | /usr/bin/awk '{print $1}')"
/bin/echo "$checksum  ${OUTPUT_PATH:t}" > "$OUTPUT_PATH.sha256"
/bin/echo "Built standard drag-to-Applications DMG: $OUTPUT_PATH"
/bin/echo "SHA-256: $checksum"
