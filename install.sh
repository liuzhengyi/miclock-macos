#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
requested_device=""
dry_run=0

usage() {
  /bin/cat <<'EOF'
Usage: ./install.sh [--device NAME_OR_UID] [--dry-run]

Builds the universal MicLock app from source and runs the transactional installer.
No Homebrew dependency is required.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --device)
      (( $# >= 2 )) || { /bin/echo "ERROR: --device requires a value" >&2; exit 2; }
      requested_device="$2"
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) /bin/echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

build_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/miclock-source-install.XXXXXX")"
trap '/bin/rm -rf "$build_dir"' EXIT
"$SOURCE_DIR/build-menu-app.sh" "$build_dir/MicLock.app"
/usr/bin/codesign --verify --deep --strict "$build_dir/MicLock.app"

if (( dry_run )); then
  /bin/echo "Dry run complete: the universal app compiled and passed signature validation."
  exit 0
fi

/usr/bin/install -m 755 "$SOURCE_DIR/distribution/install.command" "$build_dir/Install MicLock.command"
MICLOCK_NONINTERACTIVE=1 "$build_dir/Install MicLock.command"

if [[ -n "$requested_device" ]]; then
  "$HOME/Applications/MicLock.app/Contents/MacOS/MicLock" --cli use "$requested_device"
fi
