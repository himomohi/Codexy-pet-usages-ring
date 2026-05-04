#!/usr/bin/env sh
set -u

SCRIPT_PATH=$(printf '%s\n' "$0" | tr '\\' '/')
case "$SCRIPT_PATH" in
  */*) SCRIPT_DIR=${SCRIPT_PATH%/*} ;;
  *) SCRIPT_DIR=. ;;
esac
DIR=$(CDPATH= cd "$SCRIPT_DIR" && pwd) || exit 1
ROOT=$(CDPATH= cd "$DIR/../.." && pwd) || exit 1
sh "$DIR/run-powershell.sh" "$ROOT/bin/powershell/Stop.ps1" "$@"
exit $?
