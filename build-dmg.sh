#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
readonly VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$SOURCE_DIR/menu-app/Info.plist")"
readonly OUTPUT_PATH="${1:-$SOURCE_DIR/../MicLock-${VERSION}-arm64.dmg}"

build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/miclock-dmg.XXXXXX")"
trap '/bin/rm -rf "$build_dir"' EXIT
stage="$build_dir/MicLock-$VERSION"
/bin/mkdir -p "$stage" "${OUTPUT_PATH:h}"

"$SOURCE_DIR/build-menu-app.sh" "$stage/MicLock.app"
/usr/bin/install -m 755 "$SOURCE_DIR/distribution/install.command" "$stage/安装 MicLock.command"
/usr/bin/install -m 755 "$SOURCE_DIR/distribution/uninstall.command" "$stage/卸载 MicLock.command"
/usr/bin/install -m 644 "$SOURCE_DIR/distribution/使用说明.txt" "$stage/使用说明.txt"
/usr/bin/install -m 644 "$SOURCE_DIR/LICENSE" "$stage/LICENSE.txt"

/bin/rm -f "$OUTPUT_PATH"
/usr/bin/hdiutil create \
  -volname "MicLock $VERSION" \
  -srcfolder "$stage" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"
/usr/bin/codesign --force --sign - "$OUTPUT_PATH" >/dev/null
/usr/bin/hdiutil verify "$OUTPUT_PATH"

checksum="$(/usr/bin/shasum -a 256 "$OUTPUT_PATH" | /usr/bin/awk '{print $1}')"
/bin/echo "$checksum  ${OUTPUT_PATH:t}" > "$OUTPUT_PATH.sha256"
/bin/echo "Built DMG: $OUTPUT_PATH"
/bin/echo "SHA-256: $checksum"
