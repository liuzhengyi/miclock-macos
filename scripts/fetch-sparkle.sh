#!/bin/zsh
set -euo pipefail

readonly SOURCE_DIR="${0:A:h:h}"
readonly VERSION="2.10.0"
readonly EXPECTED_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
readonly DOWNLOAD_URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
readonly TARGET_DIR="$SOURCE_DIR/vendor/Sparkle-${VERSION}"
[[ ! -L "$SOURCE_DIR/vendor" && ! -L "$TARGET_DIR" ]]
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/miclock-sparkle.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
archive="$work/Sparkle.tar.xz"
curl_options=(--fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 2)
if [[ "${MICLOCK_DOWNLOAD_WITHOUT_PROXY:-0}" == "1" ]]; then curl_options+=(--noproxy '*'); fi
/usr/bin/curl "${curl_options[@]}" "$DOWNLOAD_URL" -o "$archive"
actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
[[ "$actual" == "$EXPECTED_SHA256" ]] || { /bin/echo "Sparkle official archive checksum mismatch" >&2; exit 1; }
/bin/mkdir -p "$work/extracted" "$SOURCE_DIR/vendor"
/usr/bin/tar -xJf "$archive" -C "$work/extracted"
[[ -f "$work/extracted/Sparkle.framework/Versions/B/Sparkle" ]]
/usr/bin/codesign --verify --deep --strict "$work/extracted/Sparkle.framework"
/bin/rm -rf "$TARGET_DIR"
/bin/mv "$work/extracted" "$TARGET_DIR"
/bin/echo "$EXPECTED_SHA256" > "$TARGET_DIR/.official-archive-sha256"
/bin/echo "Sparkle ${VERSION}: official archive SHA-256 and framework signature verified."
