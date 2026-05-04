#!/usr/bin/env sh
set -eu
SCRIPT_PATH=$(printf '%s\n' "$0" | tr '\\' '/')
case "$SCRIPT_PATH" in
  */*) SCRIPT_DIR=${SCRIPT_PATH%/*} ;;
  *) SCRIPT_DIR=. ;;
esac
DIR=$(CDPATH= cd "$SCRIPT_DIR" && pwd)
ROOT=$(CDPATH= cd "$DIR/../.." && pwd)
sh "$DIR/run-powershell.sh" "$ROOT/bin/powershell/Settings.ps1" "$@"
