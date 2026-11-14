#!/usr/bin/env bash
# nyx - gestionnaire d'environnements pentest conteneurisés.
# Chaque workspace est un conteneur isolé (Docker ou Podman) avec tous les outils
# de pentest, construit de façon déterministe avec Nix (dockerTools.buildLayeredImage).
# Usage : nyx <commande> [arguments]
set -euo pipefail

readonly NYX_WORKSPACE="${NYX_WORKSPACE:-$HOME/nyx-workspace}"
readonly NYX_IMAGE_PREFIX="nyx"
readonly NYX_DEFAULT_PROFILE="light"
readonly NYX_FLAKE="${NYX_FLAKE:-github:PurpleFlood/pentest-env/nix-container}"

# Auto-détection du runtime conteneur : podman prioritaire, sinon docker.
# Peut être forcé via NYX_RUNTIME=docker ou NYX_RUNTIME=podman.
detect_runtime() {
  if [[ -n "${NYX_RUNTIME:-}" ]]; then
    if command -v "$NYX_RUNTIME" &>/dev/null; then
      printf '%s' "$NYX_RUNTIME"
      return
    fi
    err "runtime '$NYX_RUNTIME' introuvable"
    exit 1
  fi
  if command -v podman &>/dev/null; then
    printf 'podman'
  elif command -v docker &>/dev/null; then
    printf 'docker'
  else
    err "ni podman ni docker n'est installé"
    exit 1
  fi
}

CTR=$(detect_runtime)
readonly CTR

info() { printf '[nyx] %s\n' "$*"; }
warn() { printf '[nyx] avertissement : %s\n' "$*" >&2; }
err()  { printf '[nyx] erreur : %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage : nyx <commande>

  install [light|full]    Construit et charge une image (défaut : light)
  uninstall [light|full]  Supprime une image
  images                  Liste les images nyx installées

  start <nom> [options]   Lance un workspace (le crée s'il n'existe pas)
    --profile full|light  Profil d'outils (défaut : light)
    --vpn <fichier.ovpn>  Connecte le VPN automatiquement

  stop <nom>              Arrête un workspace
  list                    Liste les workspaces et leur état
  rm <nom>                Supprime un workspace et ses données

Exemples :
  nyx install full
  nyx start htb-box --vpn lab.ovpn
  nyx start bounty-target --profile full
  nyx images
  nyx list
  nyx stop htb-box
  nyx rm htb-box

Runtime : $CTR
EOF
}

# ── Vérifications ────────────────────────────────────────────────────────

check_runtime() {
  if ! "$CTR" info &>/dev/null 2>&1; then
    err "$CTR n'est pas accessible (permissions ? démarré ?)"
    exit 1
  fi
}

check_nix() {
  if ! command -v nix &>/dev/null; then
    err "nix n'est pas installé (nécessaire pour construire les images)"
    exit 1
  fi
}

validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    err "nom invalide : '$name' (lettres, chiffres, '.', '_', '-' uniquement)"
    exit 1
  fi
}

# ── Helpers conteneur ────────────────────────────────────────────────────

image_exists() {
  "$CTR" image inspect "$1" &>/dev/null 2>&1
}

container_running() {
  "$CTR" ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

container_exists() {
  "$CTR" ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

# Détecte la source du flake : dépôt local si on est dedans, sinon GitHub.
detect_flake_ref() {
  local flake_dir
  flake_dir=$(pwd)
  if [[ -f "$flake_dir/flake.nix" ]] && grep -q 'docker-light\|docker-full' "$flake_dir/flake.nix" 2>/dev/null; then
    printf '%s' "$flake_dir"
  else
    printf '%s' "$NYX_FLAKE"
  fi
}

# ── Commandes : images ──────────────────────────────────────────────────

cmd_install() {
  local profile="${1:-$NYX_DEFAULT_PROFILE}"

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "profil invalide : '$profile' (light ou full)"
    exit 1
  fi

  check_nix

  local image="$NYX_IMAGE_PREFIX:$profile"

  if image_exists "$image"; then
    info "image '$image' déjà installée"
    printf '  Reconstruire ? [o/N] '
    read -r answer
    if [[ "$answer" != "o" && "$answer" != "O" ]]; then
      return
    fi
  fi

  local flake_ref
  flake_ref=$(detect_flake_ref)
  info "construction de l'image '$image' (profil: $profile)..."
  info "source : $flake_ref"
  info "cette opération peut prendre plusieurs minutes..."

  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  if ! nix build "${flake_ref}#docker-${profile}" --out-link "$tmpdir/result"; then
    err "échec de la construction de l'image"
    exit 1
  fi

  info "chargement de l'image dans $CTR..."
  "$CTR" load < "$tmpdir/result"

  info "image '$image' installée avec succès"
}

cmd_uninstall() {
  local profile="${1:-}"

  if [[ -z "$profile" ]]; then
    # Proposer les images installées
    info "images nyx installées :"
    local found=0
    for p in light full; do
      if image_exists "$NYX_IMAGE_PREFIX:$p"; then
        info "  - nyx:$p"
        found=1
      fi
    done
    if [[ $found -eq 0 ]]; then
      info "  aucune image installée"
      return
    fi
    printf '\nProfil à désinstaller (light/full) : '
    read -r profile
  fi

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "profil invalide : '$profile' (light ou full)"
    exit 1
  fi

  local image="$NYX_IMAGE_PREFIX:$profile"

  if ! image_exists "$image"; then
    info "image '$image' non installée"
    return
  fi

  # Vérifier qu'aucun conteneur n'utilise cette image
  local containers
  containers=$("$CTR" ps -a --filter "ancestor=$image" --format '{{.Names}}' 2>/dev/null) || true
  if [[ -n "$containers" ]]; then
    err "des workspaces utilisent cette image :"
    echo "$containers" | while read -r c; do info "  - ${c#nyx-}"; done
    err "supprimez-les d'abord avec 'nyx rm <nom>'"
    exit 1
  fi

  "$CTR" rmi "$image" >/dev/null
  info "image '$image' désinstallée"
}

cmd_images() {
  printf '%-15s %-12s %-15s\n' "IMAGE" "TAILLE" "ÉTAT"
  printf '%-15s %-12s %-15s\n' "-----" "------" "----"

  for profile in light full; do
    local image="$NYX_IMAGE_PREFIX:$profile"
    local state="non installée"
    local size="-"

    if image_exists "$image"; then
      state="installée"
      size=$("$CTR" image inspect "$image" --format '{{.Size}}' 2>/dev/null) || true
      # Convertir en Mo/Go lisible
      if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
        if [[ "$size" -gt 1073741824 ]]; then
          size="$(( size / 1073741824 )) Go"
        elif [[ "$size" -gt 1048576 ]]; then
          size="$(( size / 1048576 )) Mo"
        fi
      fi
    fi

    printf '%-15s %-12s %-15s\n' "nyx:$profile" "$size" "$state"
  done
}

# ── Commandes : workspaces ───────────────────────────────────────────────

cmd_start() {
  if [[ $# -lt 1 ]]; then
    err "nom du workspace manquant"
    echo "Usage : nyx start <nom> [--profile full|light] [--vpn <fichier.ovpn>]" >&2
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
        if [[ $# -lt 2 ]]; then err "--profile nécessite un argument (light|full)"; exit 1; fi
        profile="$2"
        shift 2
        ;;
      --vpn)
        if [[ $# -lt 2 ]]; then err "--vpn nécessite un chemin vers un fichier .ovpn"; exit 1; fi
        vpn="$2"
        shift 2
        ;;
      *)
        err "option inconnue : $1"
        exit 1
        ;;
    esac
  done

  if [[ "$profile" != "light" && "$profile" != "full" ]]; then
    err "profil invalide : '$profile' (light ou full)"
    exit 1
  fi

  local container="nyx-$name"
  local workspace="$NYX_WORKSPACE/$name"
  local image="$NYX_IMAGE_PREFIX:$profile"

  # Conteneur déjà actif → entrer dedans
  if container_running "$container"; then
    info "connexion au workspace '$name'..."
    exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Conteneur existant mais arrêté → redémarrer et entrer
  if container_exists "$container"; then
    info "redémarrage du workspace '$name'..."
    "$CTR" start "$container" >/dev/null
    sleep 2
    exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Vérifier que l'image existe, proposer l'install sinon
  if ! image_exists "$image"; then
    warn "image '$image' introuvable"
    printf '  Installer maintenant ? [O/n] '
    read -r answer
    if [[ "$answer" == "n" || "$answer" == "N" ]]; then
      exit 1
    fi
    cmd_install "$profile"
  fi

  # Créer le répertoire workspace sur l'hôte
  mkdir -p "$workspace"

  # Assembler les arguments de lancement
  local -a run_args=(
    --name "$container"
    --hostname "$name"
    -d
    --cap-add=NET_ADMIN
    --device=/dev/net/tun
    -v "$workspace:/workspace"
    -e "NYX_NAME=$name"
  )

  # Forwarding X11 pour les outils graphiques (Burpsuite, Firefox, Wireshark…)
  if [[ -n "${DISPLAY:-}" ]]; then
    run_args+=(-e "DISPLAY=$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix)
  fi

  # Forwarding Wayland
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    local xdg_dir
    xdg_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    run_args+=(
      -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
      -e "XDG_RUNTIME_DIR=/tmp/xdg"
      -v "$xdg_dir/$WAYLAND_DISPLAY:/tmp/xdg/$WAYLAND_DISPLAY"
    )
  fi

  # VPN : monter le fichier .ovpn dans le conteneur
  if [[ -n "$vpn" ]]; then
    if [[ ! -r "$vpn" ]]; then
      err "fichier VPN introuvable ou illisible : $vpn"
      exit 1
    fi
    local vpn_abs
    vpn_abs=$(readlink -f "$vpn")
    run_args+=(-v "$vpn_abs:/vpn/config.ovpn:ro" -e "NYX_VPN=1")
  fi

  info "lancement du workspace '$name' (profil: $profile)..."
  "$CTR" run "${run_args[@]}" "$image" >/dev/null

  # Attendre que l'entrypoint démarre
  sleep 2

  # Entrer dans le conteneur
  exec "$CTR" exec -it "$container" bash --rcfile /etc/nyx-rc -i
}

cmd_stop() {
  if [[ $# -lt 1 ]]; then
    err "nom du workspace manquant"
    exit 1
  fi
  local name="$1"
  local container="nyx-$name"

  if container_running "$container"; then
    "$CTR" stop "$container" >/dev/null
    info "workspace '$name' arrêté"
  elif container_exists "$container"; then
    info "workspace '$name' déjà arrêté"
  else
    err "workspace '$name' introuvable"
  fi
}

cmd_list() {
  if [[ ! -d "$NYX_WORKSPACE" ]]; then
    info "aucun workspace (répertoire $NYX_WORKSPACE inexistant)"
    return
  fi

  local found=0
  printf '%-20s %-10s %-10s %-6s\n' "NOM" "PROFIL" "ÉTAT" "VPN"
  printf '%-20s %-10s %-10s %-6s\n' "---" "------" "----" "---"

  for dir in "$NYX_WORKSPACE"/*/; do
    [[ -d "$dir" ]] || continue
    found=1
    local ws_name
    ws_name=$(basename "$dir")
    local container="nyx-$ws_name"
    local state="créé"
    local prof="-"
    local vpn_flag="-"

    if container_running "$container"; then
      state="actif"
    elif container_exists "$container"; then
      state="arrêté"
    fi

    if container_exists "$container"; then
      local env_dump
      env_dump=$("$CTR" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null) || true
      prof=$(echo "$env_dump" | grep '^NYX_PROFILE=' | cut -d= -f2) || true
      if echo "$env_dump" | grep -q '^NYX_VPN=1' 2>/dev/null; then
        vpn_flag="oui"
      fi
    fi

    printf '%-20s %-10s %-10s %-6s\n' "$ws_name" "${prof:-?}" "$state" "$vpn_flag"
  done

  if [[ $found -eq 0 ]]; then
    info "aucun workspace"
  fi
}

cmd_rm() {
  if [[ $# -lt 1 ]]; then
    err "nom du workspace manquant"
    exit 1
  fi
  local name="$1"
  local container="nyx-$name"
  local workspace="$NYX_WORKSPACE/$name"

  if container_running "$container"; then
    info "arrêt du conteneur..."
    "$CTR" stop "$container" >/dev/null
  fi
  if container_exists "$container"; then
    "$CTR" rm "$container" >/dev/null
  fi
  if [[ -d "$workspace" ]]; then
    rm -rf "$workspace"
    info "workspace '$name' supprimé"
  else
    err "workspace '$name' introuvable"
  fi
}

# ── Point d'entrée ──────────────────────────────────────────────────────

check_runtime

case "${1:-}" in
  install)    shift; cmd_install "$@" ;;
  uninstall)  shift; cmd_uninstall "$@" ;;
  images)     cmd_images ;;
  start)      shift; cmd_start "$@" ;;
  stop)       shift; cmd_stop "$@" ;;
  list)       cmd_list ;;
  rm)         shift; cmd_rm "$@" ;;
  -h|--help|help|"") usage ;;
  *)          err "commande inconnue : $1"; usage >&2; exit 1 ;;
esac
