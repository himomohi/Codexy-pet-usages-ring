resolve_codex_pet_root() {
  fallback_root=$1
  script_name=$2

  if [ "${CODEX_PET_USE_REPO:-}" = "1" ]; then
    printf '%s\n' "$fallback_root"
    return
  fi

  local_app_data=${LOCALAPPDATA:-}
  if [ -z "$local_app_data" ]; then
    printf '%s\n' "$fallback_root"
    return
  fi

  case "$local_app_data" in
    *\\*|?:*)
      if command -v cygpath >/dev/null 2>&1; then
        local_app_data=$(cygpath -u "$local_app_data")
      elif command -v wslpath >/dev/null 2>&1; then
        local_app_data=$(wslpath -u "$local_app_data")
      fi
      ;;
  esac

  installed_root=$local_app_data/CodexPetLimitRingsWin
  if [ -f "$installed_root/bin/powershell/$script_name" ]; then
    printf '%s\n' "$installed_root"
  else
    printf '%s\n' "$fallback_root"
  fi
}
