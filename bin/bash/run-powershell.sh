#!/usr/bin/env sh
set -u

SCRIPT=${1:-}
if [ -z "$SCRIPT" ]; then
  echo "Usage: run-powershell.sh SCRIPT.ps1 [args...]" >&2
  exit 64
fi
shift || true

if [ ! -f "$SCRIPT" ]; then
  echo "Missing PowerShell script: $SCRIPT" >&2
  exit 2
fi

UNAME=$(uname -s 2>/dev/null || echo unknown)
WINDOWS_LIKE=0
case "$UNAME" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    WINDOWS_LIKE=1
    ;;
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      WINDOWS_LIKE=1
    fi
    ;;
esac

find_powershell() {
  for candidate in powershell.exe pwsh.exe powershell pwsh; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

to_windows_path() {
  input=$1
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$input"
    return
  fi
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$input"
    return
  fi
  printf '%s\n' "$input"
}

PS_EXE=$(find_powershell || true)
if [ -z "$PS_EXE" ]; then
  echo "PowerShell was not found. Run this on Windows 10/11, Git Bash/MSYS, or WSL with powershell.exe available." >&2
  exit 127
fi

if [ "$WINDOWS_LIKE" -ne 1 ]; then
  echo "This project only supports Windows. Use Windows PowerShell, CMD, Git Bash/MSYS, or WSL with powershell.exe." >&2
  exit 1
fi

SCRIPT_FOR_PS=$SCRIPT
case "$PS_EXE" in
  *powershell.exe|*pwsh.exe|*PowerShell.exe|*pwsh.EXE)
    SCRIPT_FOR_PS=$(to_windows_path "$SCRIPT")
    ;;
esac

case "$PS_EXE" in
  *powershell.exe|*pwsh.exe|*PowerShell.exe|*pwsh.EXE)
    cmd.exe /d /c "$PS_EXE" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "$SCRIPT_FOR_PS" "$@"
    exit $?
    ;;
  *)
    "$PS_EXE" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "$SCRIPT_FOR_PS" "$@"
    exit $?
    ;;
esac
