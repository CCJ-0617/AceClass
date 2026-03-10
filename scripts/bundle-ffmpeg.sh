#!/bin/bash

set -euo pipefail

log() {
  echo "[bundle-ffmpeg] $1"
}

preferred_arch() {
  local raw_arch="${NATIVE_ARCH_ACTUAL:-${CURRENT_ARCH:-${ARCHS%% *}}}"
  if [[ -z "$raw_arch" ]]; then
    raw_arch="$(uname -m)"
  fi

  case "$raw_arch" in
    arm64|arm64e)
      printf 'arm64\n'
      ;;
    x86_64|i386)
      printf 'x86_64\n'
      ;;
    *)
      printf '%s\n' "$raw_arch"
      ;;
  esac
}

binary_supports_arch() {
  local candidate="$1"
  local target_arch="$2"
  local architectures=""

  architectures="$(lipo -archs "$candidate" 2>/dev/null || true)"
  if [[ -z "$architectures" ]]; then
    architectures="$(file -b "$candidate" 2>/dev/null || true)"
  fi

  [[ " ${architectures} " == *" ${target_arch} "* ]]
}

find_source_ffmpeg() {
  local target_arch="$1"
  local candidates=()

  if [[ -n "${ACECLASS_FFMPEG_SOURCE:-}" ]]; then
    if [[ -x "${ACECLASS_FFMPEG_SOURCE}" ]]; then
      printf '%s\n' "${ACECLASS_FFMPEG_SOURCE}"
      return 0
    fi
  fi

  if [[ -x "${PROJECT_DIR}/Vendor/ffmpeg/ffmpeg-${target_arch}" ]]; then
    candidates+=("${PROJECT_DIR}/Vendor/ffmpeg/ffmpeg-${target_arch}")
  fi

  if [[ -x "${PROJECT_DIR}/Vendor/ffmpeg/ffmpeg" ]]; then
    candidates+=("${PROJECT_DIR}/Vendor/ffmpeg/ffmpeg")
  fi

  case "$target_arch" in
    arm64)
      [[ -x "/opt/homebrew/bin/ffmpeg" ]] && candidates+=("/opt/homebrew/bin/ffmpeg")
      [[ -x "/usr/local/bin/ffmpeg" ]] && candidates+=("/usr/local/bin/ffmpeg")
      ;;
    x86_64)
      [[ -x "/usr/local/bin/ffmpeg" ]] && candidates+=("/usr/local/bin/ffmpeg")
      [[ -x "/opt/homebrew/bin/ffmpeg" ]] && candidates+=("/opt/homebrew/bin/ffmpeg")
      ;;
    *)
      [[ -x "/opt/homebrew/bin/ffmpeg" ]] && candidates+=("/opt/homebrew/bin/ffmpeg")
      [[ -x "/usr/local/bin/ffmpeg" ]] && candidates+=("/usr/local/bin/ffmpeg")
      ;;
  esac

  if command -v ffmpeg >/dev/null 2>&1; then
    candidates+=("$(command -v ffmpeg)")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]] && binary_supports_arch "$candidate" "$target_arch"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

is_vendor_dependency() {
  local path="$1"
  case "$path" in
    "${PROJECT_DIR}/Vendor/"*|/usr/local/*|/opt/homebrew/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_runtime_path() {
  local source_binary="$1"
  local runtime_path="$2"
  local source_dir
  source_dir="$(dirname "$source_binary")"

  case "$runtime_path" in
    @loader_path/*)
      printf '%s\n' "${source_dir}/${runtime_path#@loader_path/}"
      return 0
      ;;
    @executable_path/*)
      printf '%s\n' "${source_dir}/${runtime_path#@executable_path/}"
      return 0
      ;;
  esac

  return 1
}

resolve_dependency_path() {
  local source_binary="$1"
  local dependency="$2"

  if is_vendor_dependency "$dependency"; then
    printf '%s\n' "$dependency"
    return 0
  fi

  if [[ "$dependency" == @loader_path/* || "$dependency" == @executable_path/* ]]; then
    local expanded
    expanded="$(resolve_runtime_path "$source_binary" "$dependency")"
    if [[ -f "$expanded" ]] && is_vendor_dependency "$expanded"; then
      printf '%s\n' "$expanded"
      return 0
    fi
  fi

  if [[ "$dependency" == @rpath/* ]]; then
    local relative_path="${dependency#@rpath/}"
    local source_dir
    source_dir="$(dirname "$source_binary")"
    local rpath

    while IFS= read -r rpath; do
      [[ -z "$rpath" ]] && continue

      case "$rpath" in
        @loader_path/*|@executable_path/*)
          rpath="$(resolve_runtime_path "$source_binary" "$rpath")"
          ;;
      esac

      local candidate="${rpath%/}/${relative_path}"
      if [[ -f "$candidate" ]] && is_vendor_dependency "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(
      otool -l "$source_binary" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { capture = 1; next }
        capture && $1 == "path" { print $2; capture = 0 }
      '
    )
  fi

  return 1
}

copy_binary() {
  local source="$1"
  local destination="$2"

  mkdir -p "$(dirname "$destination")"
  cp -fL "$source" "$destination"
  chmod 755 "$destination"
  xattr -dr com.apple.quarantine "$destination" >/dev/null 2>&1 || true
}

rewrite_dependencies() {
  local binary_path="$1"
  local source_path="$2"
  local mode="$3"

  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue

    local resolved_dependency
    resolved_dependency="$(resolve_dependency_path "$source_path" "$dependency" || true)"
    [[ -z "$resolved_dependency" ]] && continue

    local dependency_name
    dependency_name="$(basename "$resolved_dependency")"
    local bundled_dependency="${LIB_DESTINATION}/${dependency_name}"

    if [[ ! -f "$bundled_dependency" ]]; then
      copy_binary "$resolved_dependency" "$bundled_dependency"
      echo "${bundled_dependency}|${resolved_dependency}" >> "$PENDING_FILE"
      log "Bundled dependency ${dependency_name}"
    fi

    if [[ "$mode" == "binary" ]]; then
      install_name_tool -change "$dependency" "@executable_path/lib/${dependency_name}" "$binary_path"
    else
      install_name_tool -change "$dependency" "@loader_path/${dependency_name}" "$binary_path"
    fi
  done < <(otool -L "$source_path" | tail -n +2 | awk '{print $1}')

  if [[ "$mode" == "dylib" ]]; then
    install_name_tool -id "@loader_path/$(basename "$binary_path")" "$binary_path"
  fi
}

APP_TOOLS_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Tools"
FFMPEG_DESTINATION="${APP_TOOLS_DIR}/ffmpeg"
LIB_DESTINATION="${APP_TOOLS_DIR}/lib"
PENDING_FILE="${TARGET_TEMP_DIR}/aceclass_ffmpeg_pending.txt"
PROCESSED_FILE="${TARGET_TEMP_DIR}/aceclass_ffmpeg_processed.txt"
TARGET_ARCH="$(preferred_arch)"

rm -rf "$APP_TOOLS_DIR"
rm -f "$PENDING_FILE" "$PROCESSED_FILE"
mkdir -p "$APP_TOOLS_DIR" "$LIB_DESTINATION"

if ! SOURCE_FFMPEG="$(find_source_ffmpeg "$TARGET_ARCH")"; then
  log "warning: no ${TARGET_ARCH} ffmpeg source binary found; app will fall back to system lookup at runtime"
  exit 0
fi

copy_binary "$SOURCE_FFMPEG" "$FFMPEG_DESTINATION"
rewrite_dependencies "$FFMPEG_DESTINATION" "$SOURCE_FFMPEG" "binary"

touch "$PENDING_FILE" "$PROCESSED_FILE"

line_number=1
while true; do
  pending="$(sed -n "${line_number}p" "$PENDING_FILE")"
  [[ -z "$pending" ]] && break

  IFS='|' read -r pending_path source_path <<< "$pending"

  if ! grep -Fxq "$pending_path" "$PROCESSED_FILE"; then
    rewrite_dependencies "$pending_path" "$source_path" "dylib"
    echo "$pending_path" >> "$PROCESSED_FILE"
  fi

  line_number=$((line_number + 1))
done

rmdir "$LIB_DESTINATION" >/dev/null 2>&1 || true

log "Bundled ${TARGET_ARCH} ffmpeg from ${SOURCE_FFMPEG} to ${FFMPEG_DESTINATION}"
