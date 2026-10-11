#!/bin/zsh

set -euo pipefail

readonly SOURCE_DIR="${0:A:h}"
[[ $# == 0 ]] || {
  /bin/echo "Usage: ./uninstall.sh" >&2
  exit 2
}
MICLOCK_NONINTERACTIVE=1 "$SOURCE_DIR/distribution/uninstall.command"
