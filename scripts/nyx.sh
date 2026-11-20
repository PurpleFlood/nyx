#!/usr/bin/env bash
# nyx - containerised pentest workspace manager.
# Each workspace is an isolated container (Docker or Podman) with all pentest
# tools, built deterministically with Nix (dockerTools.buildLayeredImage).
# Usage: nyx <command> [arguments]
set -euo pipefail

readonly NYX_WORKSPACE="${NYX_WORKSPACE:-$HOME/nyx-workspace}"
readonly NYX_IMAGE_PREFIX="nyx"
readonly NYX_DEFAULT_PROFILE="light"
readonly NYX_FLAKE="${NYX_FLAKE:-github:PurpleFlood/pentest-env/nix-container}"
readonly NYX_BUILD_DIR="${NYX_BUILD_DIR:-$HOME/.nyx/build}"

# Auto-detect container runtime: podman preferred, fallback to docker.
# Override with NYX_RUNTIME=docker or NYX_RUNTIME=podman.
detect_runtime() {
  if [[ -n "${NYX_RUNTIME:-}" ]]; then
    if command -v "$NYX_RUNTIME" &>/dev/null; then
      printf '%s' "$NYX_RUNTIME"
      return
    fi
    err "runtime '$NYX_RUNTIME' not found"
    exit 1
  fi
  if command -v podman &>/dev/null; then
    printf 'podman'
  elif command -v docker &>/dev/null; then
    printf 'docker'
  else
    err "neither podman nor docker is installed"
    exit 1
  fi
}

CTR=$(detect_runtime)
readonly CTR

info() { printf '[nyx] %s\n' "$*"; }
warn() { printf '[nyx] warning: %s\n' "$*" >&2; }
err()  { printf '[nyx] error: %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: nyx <command>

  install [light|full]    Build and load an image (default: light)
  uninstall [light|full]  Remove an image
  update [light|full]     Update an image (rebuild from flake)
  images                  List installed nyx images

  start <name> [options]  Start a workspace (creates it if needed)
    --profile full|light  Tool profile (default: light)
    --vpn <file.ovpn>     Connect VPN automatically

  stop <name>             Stop a workspace
  restart <name> [options] Recreate container with latest image
    --profile full|light  Switch tool profile
  list                    List workspaces and their status
  rm <name>               Remove a workspace and its data

Examples:
  nyx install full
  nyx update full
  nyx start htb-box --vpn lab.ovpn
  nyx start bounty-target --profile full
  nyx restart htb-box --profile full
  nyx images
  nyx list
  nyx stop htb-box
  nyx rm htb-box

Runtime: $CTR
EOF
}

# ── Checks ──────────────────────────────────────────────────────────────

check_runtime() {
  if ! "$CTR" info &>/dev/null 2>&1; then
    err "$CTR is not accessible (permissions? running?)"
    exit 1
  fi
}

check_nix() {
  if ! command -v nix &>/dev/null; then
    err "nix is not installed (required to build images)"
    exit 1
  fi
}

validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    err "invalid name: '$name' (letters, digits, '.', '_', '-' only)"
    exit 1
  fi
}

# ── Container helpers ───────────────────────────────────────────────────

image_exists() {
  "$CTR" image inspect "$1" &>/dev/null 2>&1
}

container_running() {
  "$CTR" ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

container_exists() {
  "$CTR" ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

# Get the profile of an existing container.
get_container_profile() {
  local container="$1"
  "$CTR" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null \
    | grep '^NYX_PROFILE=' | cut -d= -f2
}

# Get the host path of the VPN file mounted in a container.
get_container_vpn() {
  local container="$1"
  "$CTR" inspect --format '{{range .Mounts}}{{if eq .Destination "/vpn/config.ovpn"}}{{.Source}}{{end}}{{end}}' "$container" 2>/dev/null || true
}

# Check if the container's image differs from the current one.
# Returns 0 (true) if the container uses an older image version.
container_image_outdated() {
  local container="$1"
  local profile="$2"
  local image="$NYX_IMAGE_PREFIX:$profile"

  local container_image_id current_image_id
  container_image_id=$("$CTR" inspect --format '{{.Image}}' "$container" 2>/dev/null) || return 1
  current_image_id=$("$CTR" image inspect --format '{{.Id}}' "$image" 2>/dev/null) || return 1

  [[ "$container_image_id" != "$current_image_id" ]]
}

# Create a container with standard args (X11, Wayland, VPN…).
# Usage: create_container <name> <profile> [vpn_path]
create_container() {
  local name="$1"
  local profile="$2"
  local vpn="${3:-}"

  local container="nyx-$name"
  local workspace="$NYX_WORKSPACE/$name"
  local image="$NYX_IMAGE_PREFIX:$profile"

  mkdir -p "$workspace"

  local -a run_args=(
    --name "$container"
    --hostname "$name"
    -d
    --privileged
    --device=/dev/net/tun
    -v "$workspace:/workspace"
    -e "NYX_NAME=$name"
  )

  # X11 forwarding
  if [[ -n "${DISPLAY:-}" ]]; then
    run_args+=(-e "DISPLAY=$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix)
  fi

  # Wayland forwarding
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    local xdg_dir
    xdg_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    run_args+=(
      -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
      -e "XDG_RUNTIME_DIR=/tmp/xdg"
      -v "$xdg_dir/$WAYLAND_DISPLAY:/tmp/xdg/$WAYLAND_DISPLAY"
    )
  fi

  # VPN
  if [[ -n "$vpn" && -r "$vpn" ]]; then
    local vpn_abs
    vpn_abs=$(readlink -f "$vpn")
    run_args+=(-v "$vpn_abs:/vpn/config.ovpn:ro" -e "NYX_VPN=1")
  fi

  "$CTR" run "${run_args[@]}" "$image" >/dev/null
}

# Detect flake source: local repo if inside one, otherwise GitHub.
detect_flake_ref() {
  local flake_dir
  flake_dir=$(pwd)
  if [[ -f "$flake_dir/flake.nix" ]] && grep -q 'docker-light\|docker-full' "$flake_dir/flake.nix" 2>/dev/null; then
    printf '%s' "$flake_dir"
  else
    printf '%s' "$NYX_FLAKE"
  fi
}

# ── Commands: images ───────────────────────────────────────────────────

cmd_install() {
  local profile="${1:-$NYX_DEFAULT_PROFILE}"

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "invalid profile: '$profile' (light or full)"
    exit 1
  fi

  check_nix

  local image="$NYX_IMAGE_PREFIX:$profile"

  if image_exists "$image"; then
    info "image '$image' already installed"
    printf '  Rebuild? [y/N] '
    read -r answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
      return
    fi
  fi

  local flake_ref
  flake_ref=$(detect_flake_ref)
  info "building image '$image' (profile: $profile)..."
  info "source: $flake_ref"
  info "this may take several minutes..."

  mkdir -p "$NYX_BUILD_DIR"

  if ! nix build "${flake_ref}#docker-${profile}" --out-link "$NYX_BUILD_DIR/result"; then
    err "image build failed"
    exit 1
  fi

  export TMPDIR="$NYX_BUILD_DIR"

  info "loading image into $CTR..."
  "$CTR" load < "$NYX_BUILD_DIR/result"

  info "image '$image' installed successfully"
}

cmd_uninstall() {
  local profile="${1:-}"

  if [[ -z "$profile" ]]; then
    info "installed nyx images:"
    local found=0
    for p in light full; do
      if image_exists "$NYX_IMAGE_PREFIX:$p"; then
        info "  - nyx:$p"
        found=1
      fi
    done
    if [[ $found -eq 0 ]]; then
      info "  no images installed"
      return
    fi
    printf '\nProfile to uninstall (light/full): '
    read -r profile
  fi

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "invalid profile: '$profile' (light or full)"
    exit 1
  fi

  local image="$NYX_IMAGE_PREFIX:$profile"

  if ! image_exists "$image"; then
    info "image '$image' not installed"
    return
  fi

  # Stop and remove containers using this image
  local containers
  containers=$("$CTR" ps -a --filter "ancestor=$image" --format '{{.Names}}' 2>/dev/null) || true
  if [[ -n "$containers" ]]; then
    info "removing containers linked to this image:"
    echo "$containers" | while read -r c; do
      info "  - ${c#nyx-}"
      "$CTR" stop "$c" &>/dev/null || true
      "$CTR" rm "$c" &>/dev/null || true
    done
  fi

  "$CTR" rmi "$image" >/dev/null
  info "image '$image' uninstalled"
}

cmd_update() {
  local profile="${1:-}"

  check_nix

  # No profile specified → update all installed images
  if [[ -z "$profile" ]]; then
    local installed=()
    for p in light full; do
      if image_exists "$NYX_IMAGE_PREFIX:$p"; then
        installed+=("$p")
      fi
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
      info "no images installed, nothing to update"
      return
    fi

    info "installed images: ${installed[*]}"
    printf '  Update all images? [Y/n] '
    read -r answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
      return
    fi

    for p in "${installed[@]}"; do
      cmd_update "$p"
    done
    return
  fi

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "invalid profile: '$profile' (light or full)"
    exit 1
  fi

  local image="$NYX_IMAGE_PREFIX:$profile"

  if ! image_exists "$image"; then
    err "image '$image' not installed, use 'nyx install $profile'"
    exit 1
  fi

  info "updating image '$image'..."

  check_nix

  local image="$NYX_IMAGE_PREFIX:$profile"

  if ! image_exists "$image"; then
    info "image '$image' not installed, installing..."
  else
    info "updating image '$image'..."
  fi

  local flake_ref
  flake_ref=$(detect_flake_ref)
  info "source: $flake_ref"
  info "this may take several minutes..."

  mkdir -p "$NYX_BUILD_DIR"

  if ! nix build "${flake_ref}#docker-${profile}" --out-link "$NYX_BUILD_DIR/result"; then
    err "image build failed"
    exit 1
  fi

  export TMPDIR="$NYX_BUILD_DIR"

  info "loading image into $CTR..."
  "$CTR" load < "$NYX_BUILD_DIR/result"

  info "image '$image' updated successfully"

  # List affected workspaces
  local outdated=""
  if [[ -d "$NYX_WORKSPACE" ]]; then
    for dir in "$NYX_WORKSPACE"/*/; do
      [[ -d "$dir" ]] || continue
      local ws_name
      ws_name=$(basename "$dir")
      local container="nyx-$ws_name"
      if container_exists "$container"; then
        local ws_profile
        ws_profile=$(get_container_profile "$container")
        if [[ "${ws_profile:-}" == "$profile" ]]; then
          outdated+="  - $ws_name"$'\n'
        fi
      fi
    done
  fi

  if [[ -n "$outdated" ]]; then
    info "workspaces using nyx:$profile:"
    printf '%s' "$outdated"
    info "use 'nyx restart <name>' to apply the update"
  fi
}

cmd_images() {
  printf '%-15s %-12s %-15s\n' "IMAGE" "SIZE" "STATUS"
  printf '%-15s %-12s %-15s\n' "-----" "----" "------"

  for profile in light full; do
    local image="$NYX_IMAGE_PREFIX:$profile"
    local state="not installed"
    local size="-"

    if image_exists "$image"; then
      state="installed"
      size=$("$CTR" image inspect "$image" --format '{{.Size}}' 2>/dev/null) || true
      # Convert to human-readable MB/GB
      if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
        if [[ "$size" -gt 1073741824 ]]; then
          size="$(( size / 1073741824 )) GB"
        elif [[ "$size" -gt 1048576 ]]; then
          size="$(( size / 1048576 )) MB"
        fi
      fi
    fi

    printf '%-15s %-12s %-15s\n' "nyx:$profile" "$size" "$state"
  done
}

# ── Commands: workspaces ────────────────────────────────────────────────

cmd_start() {
  if [[ $# -lt 1 ]]; then
    err "missing workspace name"
    echo "Usage: nyx start <name> [--profile full|light] [--vpn <file.ovpn>]" >&2
    exit 1
  fi

  local name="$1"
  shift
  validate_name "$name"

  local profile="$NYX_DEFAULT_PROFILE"
  local vpn=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        if [[ $# -lt 2 ]]; then err "--profile requires an argument (light|full)"; exit 1; fi
        profile="$2"
        shift 2
        ;;
      --vpn)
        if [[ $# -lt 2 ]]; then err "--vpn requires a path to an .ovpn file"; exit 1; fi
        vpn="$2"
        shift 2
        ;;
      *)
        err "unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "invalid profile: '$profile' (light or full)"
    exit 1
  fi

  local container="nyx-$name"
  local workspace="$NYX_WORKSPACE/$name"
  local image="$NYX_IMAGE_PREFIX:$profile"

  # Container already running → attach
  if container_running "$container"; then
    info "connecting to workspace '$name'..."
    exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Container exists but stopped → check for update and restart
  if container_exists "$container"; then
    local current_profile
    current_profile=$(get_container_profile "$container")

    # Detect image update
    if container_image_outdated "$container" "${current_profile:-$profile}"; then
      warn "an image update for nyx:${current_profile:-$profile} is available"
      printf '  Update workspace? [Y/n] '
      read -r answer
      if [[ "$answer" != "n" && "$answer" != "N" ]]; then
        info "updating workspace '$name'..."
        local vpn_path
        vpn_path=$(get_container_vpn "$container")
        if container_running "$container"; then
          "$CTR" stop "$container" >/dev/null
        fi
        "$CTR" rm "$container" >/dev/null
        create_container "$name" "${current_profile:-$profile}" "$vpn_path"
        sleep 2
        exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
      fi
    fi

    info "restarting workspace '$name'..."
    "$CTR" start "$container" >/dev/null
    sleep 2
    exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Check image exists, offer install if missing
  if ! image_exists "$image"; then
    warn "image '$image' not found"
    printf '  Install now? [Y/n] '
    read -r answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
      exit 1
    fi
    cmd_install "$profile"
  fi

  # New workspace
  if [[ -n "$vpn" && ! -r "$vpn" ]]; then
    err "VPN file not found or unreadable: $vpn"
    exit 1
  fi

  info "starting workspace '$name' (profile: $profile)..."
  create_container "$name" "$profile" "$vpn"

  # Wait for entrypoint to start
  sleep 2

  # Enter the container
  exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
}

cmd_stop() {
  if [[ $# -lt 1 ]]; then
    err "missing workspace name"
    exit 1
  fi
  local name="$1"
  local container="nyx-$name"

  if container_running "$container"; then
    "$CTR" stop "$container" >/dev/null
    info "workspace '$name' stopped"
  elif container_exists "$container"; then
    info "workspace '$name' already stopped"
  else
    err "workspace '$name' not found"
  fi
}

cmd_restart() {
  if [[ $# -lt 1 ]]; then
    err "missing workspace name"
    echo "Usage: nyx restart <name> [--profile full|light]" >&2
    exit 1
  fi

  local name="$1"
  shift
  validate_name "$name"

  local container="nyx-$name"
  local new_profile=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        if [[ $# -lt 2 ]]; then err "--profile requires an argument (light|full)"; exit 1; fi
        new_profile="$2"
        shift 2
        ;;
      *)
        err "unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [[ -n "$new_profile" && "$new_profile" != "light" && "$new_profile" != "full" ]]; then
    err "invalid profile: '$new_profile' (light or full)"
    exit 1
  fi

  if ! container_exists "$container"; then
    err "workspace '$name' not found"
    exit 1
  fi

  # Get current container info
  local current_profile vpn_path
  current_profile=$(get_container_profile "$container")
  vpn_path=$(get_container_vpn "$container")

  local profile="${new_profile:-${current_profile:-$NYX_DEFAULT_PROFILE}}"
  local image="$NYX_IMAGE_PREFIX:$profile"

  # Check image exists
  if ! image_exists "$image"; then
    warn "image '$image' not found"
    printf '  Install now? [Y/n] '
    read -r answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
      exit 1
    fi
    cmd_install "$profile"
  fi

  if [[ -n "$new_profile" && "$new_profile" != "${current_profile:-}" ]]; then
    info "switching profile: ${current_profile:-?} → $new_profile"
  fi

  # Stop if running
  if container_running "$container"; then
    info "stopping workspace '$name'..."
    "$CTR" stop "$container" >/dev/null
  fi

  # Remove container (not the volume!)
  "$CTR" rm "$container" >/dev/null

  # Recreate with the new image
  info "recreating workspace '$name' (profile: $profile)..."
  create_container "$name" "$profile" "$vpn_path"

  sleep 2
  exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
}

cmd_list() {
  if [[ ! -d "$NYX_WORKSPACE" ]]; then
    info "no workspaces ($NYX_WORKSPACE does not exist)"
    return
  fi

  local found=0
  printf '%-20s %-10s %-10s %-6s\n' "NAME" "PROFILE" "STATUS" "VPN"
  printf '%-20s %-10s %-10s %-6s\n' "----" "-------" "------" "---"

  for dir in "$NYX_WORKSPACE"/*/; do
    [[ -d "$dir" ]] || continue
    found=1
    local ws_name
    ws_name=$(basename "$dir")
    local container="nyx-$ws_name"
    local state="created"
    local prof="-"
    local vpn_flag="-"

    if container_running "$container"; then
      state="running"
    elif container_exists "$container"; then
      state="stopped"
    fi

    if container_exists "$container"; then
      local env_dump
      env_dump=$("$CTR" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null) || true
      prof=$(echo "$env_dump" | grep '^NYX_PROFILE=' | cut -d= -f2) || true
      if echo "$env_dump" | grep -q '^NYX_VPN=1' 2>/dev/null; then
        vpn_flag="yes"
      fi
    fi

    printf '%-20s %-10s %-10s %-6s\n' "$ws_name" "${prof:-?}" "$state" "$vpn_flag"
  done

  if [[ $found -eq 0 ]]; then
    info "no workspaces"
  fi
}

cmd_rm() {
  if [[ $# -lt 1 ]]; then
    err "missing workspace name"
    exit 1
  fi
  local name="$1"
  local container="nyx-$name"
  local workspace="$NYX_WORKSPACE/$name"

  if container_running "$container"; then
    info "stopping container..."
    "$CTR" stop "$container" >/dev/null
  fi
  if container_exists "$container"; then
    "$CTR" rm "$container" >/dev/null
  fi
  if [[ -d "$workspace" ]]; then
    rm -rf "$workspace"
    info "workspace '$name' removed"
  else
    err "workspace '$name' not found"
  fi
}

# ── Entry point ─────────────────────────────────────────────────────────

check_runtime

case "${1:-}" in
  install)    shift; cmd_install "$@" ;;
  uninstall)  shift; cmd_uninstall "$@" ;;
  update)     shift; cmd_update "$@" ;;
  images)     cmd_images ;;
  start)      shift; cmd_start "$@" ;;
  stop)       shift; cmd_stop "$@" ;;
  restart)    shift; cmd_restart "$@" ;;
  list)       cmd_list ;;
  rm)         shift; cmd_rm "$@" ;;
  -h|--help|help|"") usage ;;
  *)          err "unknown command: $1"; usage >&2; exit 1 ;;
esac
