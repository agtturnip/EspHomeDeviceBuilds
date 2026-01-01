#!/usr/bin/env bash
set -euo pipefail

# Print usage help.
usage() {
  cat <<'USAGE'
Usage:
  scripts/export_build.sh <build_dir>
  scripts/export_build.sh all
  scripts/export_build.sh

Notes:
  - With a build_dir or "all", this script exports a single YAML (same as before).
  - With no args, it runs in interactive mode to export YAML, build bins, or upload.
USAGE
}

# Resolve repo root so the script can run from any working directory.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builds_dir="$root_dir/builds"

# Ensure the esphome CLI is available before running any commands.
require_esphome() {
  if ! command -v esphome >/dev/null 2>&1; then
    echo "esphome CLI not found in PATH." >&2
    return 1
  fi
}

# Detect common USB serial device paths (avoid Bluetooth tty.* noise).
has_serial_device() {
  local patterns=(
    "/dev/ttyUSB*"
    "/dev/ttyACM*"
    "/dev/tty.usbserial*"
    "/dev/tty.usbmodem*"
    "/dev/tty.SLAB_USBtoUART*"
    "/dev/tty.wchusbserial*"
    "/dev/cu.usbserial*"
    "/dev/cu.usbmodem*"
    "/dev/cu.SLAB_USBtoUART*"
    "/dev/cu.wchusbserial*"
  )
  local pattern
  for pattern in "${patterns[@]}"; do
    if compgen -G "$pattern" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Ask a yes/no question (default: no).
prompt_yes_no() {
  local prompt="$1"
  local reply

  echo "$prompt" >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Normalize a build dir to an absolute path under the repo.
normalize_build_dir() {
  local input="$1"
  if [[ "$input" = /* ]]; then
    echo "$input"
  else
    echo "$root_dir/$input"
  fi
}

# Ensure required files exist in the build folder.
require_build_files() {
  local build_dir="$1"
  if [[ ! -f "$build_dir/build.yaml" ]]; then
    echo "Missing build.yaml in $build_dir" >&2
    return 1
  fi
}

# Ensure secrets exist for this build (needed for esphome commands).
require_secrets() {
  local build_dir="$1"
  if [[ ! -f "$build_dir/secrets.yaml" ]]; then
    echo "Missing secrets.yaml in $build_dir. Copy secrets.example.yaml first." >&2
    return 1
  fi
}

# Render a single build into export/<device>.yaml with secrets expanded.
export_yaml() {
  local build_dir="$1"
  local build_yaml="$build_dir/build.yaml"
  local export_dir="$build_dir/export"
  local name
  local out

  require_esphome
  require_build_files "$build_dir"
  require_secrets "$build_dir"

  name="$(basename "$build_dir")"
  out="$export_dir/${name}.yaml"

  mkdir -p "$export_dir"
  # Expand packages/substitutions into a single YAML (includes secrets).
  esphome config --show-secrets "$build_yaml" > "$out"
  echo "Wrote $out"
}

# Compile a build to produce firmware binaries.
compile_build() {
  local build_dir="$1"
  local build_yaml="$build_dir/build.yaml"

  require_esphome
  require_build_files "$build_dir"
  require_secrets "$build_dir"

  esphome compile "$build_yaml"
}

# Upload a build to a device (includes compile and logs).
# Upload mode: \"run\" (compile + upload + logs) or \"upload\" (upload only).
run_build() {
  local build_dir="$1"
  local mode="${2:-run}"
  local build_yaml="$build_dir/build.yaml"

  require_esphome
  require_build_files "$build_dir"
  require_secrets "$build_dir"

  # If no serial device is detected, offer OTA instead of failing silently.
  if ! has_serial_device; then
    echo "No serial devices detected." >&2
    if prompt_yes_no "Attempt OTA upload instead? (requires device on Wi-Fi) [y/N]"; then
      if [[ "$mode" == "upload" ]]; then
        esphome upload "$build_yaml"
      else
        esphome run "$build_yaml"
      fi
    else
      echo "Skipping upload (no serial device)." >&2
    fi
    return 0
  fi

  if [[ "$mode" == "upload" ]]; then
    esphome upload "$build_yaml"
  else
    esphome run "$build_yaml"
  fi
}

# Copy compiled firmware binaries into export/.
copy_bins() {
  local build_dir="$1"
  local export_dir="$build_dir/export"
  local cache_dir="$build_dir/.esphome/build"
  local found=0

  if [[ ! -d "$cache_dir" ]]; then
    echo "No build cache found in $build_dir. Compile first." >&2
    return 1
  fi

  mkdir -p "$export_dir"

  # Copy firmware bin outputs (factory/ota). These appear after compile/run.
  while IFS= read -r -d '' bin; do
    found=1
    cp "$bin" "$export_dir/$(basename "$bin")"
  done < <(find "$cache_dir" -type f -name "firmware*.bin" -print0)

  if [[ $found -eq 0 ]]; then
    echo "No firmware*.bin files found. Compile first." >&2
    return 1
  fi

  echo "Copied firmware bin files to $export_dir"
}

# Discover build folders (one level under builds/), skipping _template.
list_build_dirs() {
  local -a dirs=()
  local build_yaml

  while IFS= read -r -d '' build_yaml; do
    local dir
    dir="$(dirname "$build_yaml")"
    if [[ "$(basename "$dir")" == "_template" ]]; then
      continue
    fi
    dirs+=("$dir")
  done < <(find "$builds_dir" -mindepth 2 -maxdepth 2 -type f -name build.yaml -print0)

  if [[ ${#dirs[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${dirs[@]}" | sort
}

# Prompt the user to select a build folder.
select_build_dir() {
  local -a dirs=()
  local dir
  local i
  local selection

  while IFS= read -r dir; do
    dirs+=("$dir")
  done < <(list_build_dirs)

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No build folders found under builds/." >&2
    exit 1
  fi

  echo "Select a build:" >&2
  for i in "${!dirs[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${dirs[$i]#"$root_dir"/}" >&2
  done

  read -r selection
  if [[ ! "$selection" =~ ^[0-9]+$ ]] || ((selection < 1 || selection > ${#dirs[@]})); then
    echo "Invalid selection." >&2
    exit 1
  fi

  echo "${dirs[$((selection - 1))]}"
}

# Prompt the user to select an action.
select_action() {
  cat >&2 <<'MENU'
Choose an action:
  1) Export YAML to export/
  2) Compile and copy .bin to export/
  3) Compile and upload to device (esphome run)
  4) All of the above
MENU
  read -r action
  echo "$action"
}

# Non-interactive behavior (backward compatible): export YAML only.
if [[ $# -eq 1 ]]; then
  target="$1"
  case "$target" in
    -h|--help)
      usage
      exit 0
      ;;
    all)
      while IFS= read -r dir; do
        export_yaml "$dir"
      done < <(list_build_dirs)
      ;;
    *)
      export_yaml "$(normalize_build_dir "$target")"
      ;;
  esac
  exit 0
fi

# Interactive mode when no args are provided.
if [[ $# -eq 0 ]]; then
  build_dir="$(select_build_dir)"
  action="$(select_action)"

  case "$action" in
    1)
      export_yaml "$build_dir"
      ;;
    2)
      compile_build "$build_dir"
      copy_bins "$build_dir"
      ;;
    3)
      run_build "$build_dir"
      ;;
    4)
      export_yaml "$build_dir"
      compile_build "$build_dir"
      run_build "$build_dir" "upload"
      copy_bins "$build_dir"
      ;;
    *)
      echo "Invalid action." >&2
      exit 1
      ;;
  esac
  exit 0
fi

usage
exit 1
