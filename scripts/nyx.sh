#!/usr/bin/env bash
# nyx - gestionnaire d'environnements pentest conteneurisés.
# Chaque workspace est un conteneur Docker isolé avec tous les outils de pentest,
# construit de façon déterministe avec Nix (dockerTools.buildLayeredImage).
# Usage : nyx <start|stop|list|rm> [arguments]
set -euo pipefail

readonly NYX_WORKSPACE="${NYX_WORKSPACE:-$HOME/nyx-workspace}"
readonly NYX_IMAGE_PREFIX="nyx"
readonly NYX_DEFAULT_PROFILE="light"

info() { printf '[nyx] %s\n' "$*"; }
warn() { printf '[nyx] avertissement : %s\n' "$*" >&2; }
err()  { printf '[nyx] erreur : %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage : nyx <commande>

  start <nom> [options]   Lance un environnement (le crée s'il n'existe pas)
    --profile full|light  Profil d'outils (défaut : light)
    --vpn <fichier.ovpn>  Connecte le VPN automatiquement

  stop <nom>              Arrête un environnement
  list                    Liste les environnements et leur état
  rm <nom>                Supprime un environnement et ses données

Exemples :
  nyx start htb-box --vpn lab.ovpn
  nyx start bounty-target --profile full
  nyx list
  nyx stop htb-box
  nyx rm htb-box
EOF
}

# ── Vérifications ────────────────────────────────────────────────────────

check_docker() {
  if ! command -v docker &>/dev/null; then
    err "docker n'est pas installé ou pas dans le PATH"
    exit 1
  fi
  if ! docker info &>/dev/null 2>&1; then
    err "le daemon docker n'est pas accessible (permissions ? démarré ?)"
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

# ── Helpers Docker ───────────────────────────────────────────────────────

image_exists() {
  docker image inspect "$1" &>/dev/null 2>&1
}

container_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

container_exists() {
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

# ── Commandes ────────────────────────────────────────────────────────────

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
    exec docker exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Conteneur existant mais arrêté → redémarrer et entrer
  if container_exists "$container"; then
    info "redémarrage du workspace '$name'..."
    docker start "$container" >/dev/null
    sleep 2
    exec docker exec -it "$container" bash --rcfile /etc/nyx-rc -i
  fi

  # Vérifier que l'image Docker existe
  if ! image_exists "$image"; then
    err "image '$image' introuvable dans Docker"
    info "construisez-la avec :"
    info "  nix build .#docker-$profile && docker load < result"
    exit 1
  fi

  # Créer le répertoire workspace sur l'hôte
  mkdir -p "$workspace"

  # Assembler les arguments docker run
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
  docker run "${run_args[@]}" "$image" >/dev/null

  # Attendre que l'entrypoint démarre
  sleep 2

  # Entrer dans le conteneur
  exec docker exec -it "$container" bash --rcfile /etc/nyx-rc -i
}

cmd_stop() {
  if [[ $# -lt 1 ]]; then
    err "nom du workspace manquant"
    exit 1
  fi
  local name="$1"
  local container="nyx-$name"

  if container_running "$container"; then
    docker stop "$container" >/dev/null
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
      env_dump=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null) || true
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
    docker stop "$container" >/dev/null
  fi
  if container_exists "$container"; then
    docker rm "$container" >/dev/null
  fi
  if [[ -d "$workspace" ]]; then
    rm -rf "$workspace"
    info "workspace '$name' supprimé"
  else
    err "workspace '$name' introuvable"
  fi
}

# ── Point d'entrée ──────────────────────────────────────────────────────

check_docker

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  stop)   shift; cmd_stop "$@" ;;
  list)   cmd_list ;;
  rm)     shift; cmd_rm "$@" ;;
  -h|--help|help|"") usage ;;
  *)      err "commande inconnue : $1"; usage >&2; exit 1 ;;
esac
