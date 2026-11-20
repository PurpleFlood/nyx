#!/usr/bin/env bash
# Gestion d'un VPN CTF (HTB/THM) isolé dans un network namespace.
# Le trafic du namespace sort par l'interface physique de l'hôte (table de routage dédiée),
# jamais par wg0 : le WireGuard de l'hôte reste intact.
# Usage : ctf-vpn <start <fichier.ovpn> | shell | status | stop>
set -euo pipefail

readonly NS="pentest-ns"
readonly VETH_HOST="veth-host"
readonly VETH_NS="veth-pentest"
readonly HOST_IP="10.200.1.1"
readonly NS_IP="10.200.1.2"
readonly SUBNET="10.200.1.0/24"
readonly RT_TABLE="100"
readonly RULE_PRIO="1000"
readonly STATE_DIR="/run/ctf-vpn"
readonly STATE_FILE="$STATE_DIR/state"
readonly PID_FILE="$STATE_DIR/openvpn.pid"
readonly OVPN_LOG="$STATE_DIR/openvpn.log"
readonly NETNS_ETC="/etc/netns/$NS"

info() { printf '[ctf-vpn] %s\n' "$*"; }
warn() { printf '[ctf-vpn] avertissement : %s\n' "$*" >&2; }
err() { printf '[ctf-vpn] erreur : %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage : ctf-vpn <commande>
  start <fichier.ovpn>  crée le namespace et lance OpenVPN dedans
  shell                 ouvre un shell dans le namespace VPN
  status                affiche l'état du namespace et du VPN
  stop                  arrête OpenVPN et nettoie le namespace
EOF
}

# Relance le script en root (opérations réseau) en conservant l'environnement
# pour que le shell du namespace hérite de DISPLAY, PATH, PENTEST_RC, etc.
PATH_FILE="/tmp/ctf-vpn-caller-path.$(id -u)"
readonly PATH_FILE
if [[ $EUID -ne 0 ]]; then
  case "${1:-}" in
    -h|--help|help|"") usage; exit 0 ;;
  esac
  printf '%s' "$PATH" > "$PATH_FILE"
  exec sudo -E -- "$0" "$@"
fi

REAL_USER="${SUDO_USER:-root}"
REAL_UID="${SUDO_UID:-0}"
REAL_GID="${SUDO_GID:-0}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -r "/tmp/ctf-vpn-caller-path.${SUDO_UID:-0}" ]]; then
  CALLER_PATH="$(cat "/tmp/ctf-vpn-caller-path.${SUDO_UID:-0}")"
else
  CALLER_PATH="${CTF_CALLER_PATH:-$PATH}"
fi

namespace_exists() {
  ip netns list | awk '{print $1}' | grep -qx "$NS"
}

vpn_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# Interface de sortie : route par défaut hors WireGuard, tunnels et veth.
detect_uplink() {
  local line
  line=$(ip -4 route show default | awk '$0 !~ /dev (wg|tun|tap|veth|tailscale)/ { print; exit }') || true
  if [[ -z "$line" ]]; then
    err "aucune route par défaut hors WireGuard : impossible de sortir par l'interface physique"
    return 1
  fi
  UPLINK_GW=$(awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }' <<<"$line")
  UPLINK_IF=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$line")
  if [[ -z "$UPLINK_GW" || -z "$UPLINK_IF" ]]; then
    err "route par défaut incomplète : $line"
    return 1
  fi
}

write_state() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  cat >"$STATE_FILE" <<EOF
UPLINK_IF="$UPLINK_IF"
UPLINK_GW="$UPLINK_GW"
PREV_IP_FORWARD="$PREV_IP_FORWARD"
EOF
}

# Annule tout ce que start a pu créer ; chaque étape tolère l'absence de la ressource.
teardown() {
  local uplink_if="" prev_fwd=""
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    uplink_if="${UPLINK_IF:-}"
    prev_fwd="${PREV_IP_FORWARD:-}"
  fi

  if namespace_exists; then
    ip netns pids "$NS" 2>/dev/null | while read -r p; do kill "$p" 2>/dev/null || true; done || true
  fi
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
  fi
  sleep 1

  ip rule del from "$SUBNET" lookup "$RT_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
  ip route flush table "$RT_TABLE" 2>/dev/null || true

  if [[ -n "$uplink_if" ]]; then
    iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$uplink_if" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$VETH_HOST" -o "$uplink_if" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$uplink_if" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  fi

  ip link del "$VETH_HOST" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  rm -rf "$NETNS_ETC"

  if [[ -n "$prev_fwd" ]]; then
    sysctl -qw "net.ipv4.ip_forward=$prev_fwd" || true
  fi

  rm -f "$PID_FILE" "$STATE_FILE"
}

wait_vpn() {
  for _ in $(seq 1 60); do
    if grep -q 'Initialization Sequence Completed' "$OVPN_LOG" 2>/dev/null; then
      return 0
    fi
    if grep -qE 'AUTH_FAILED|Exiting due to fatal error|Options error' "$OVPN_LOG" 2>/dev/null; then
      return 1
    fi
    sleep 1
  done
  return 1
}

on_start_exit() {
  local rc=$?
  if [[ $STARTED -ne 1 ]]; then
    warn "échec du démarrage : nettoyage du namespace"
    teardown
  fi
  exit "$rc"
}

cmd_start() {
  local ovpn="${1:-}"
  if [[ -z "$ovpn" ]]; then
    err "fichier .ovpn manquant (ctf-vpn start <fichier.ovpn>)"
    exit 1
  fi
  if [[ ! -r "$ovpn" ]]; then
    err "fichier introuvable ou illisible : $ovpn"
    exit 1
  fi
  ovpn=$(readlink -f "$ovpn")

  if namespace_exists; then
    if vpn_running; then
      info "le VPN est déjà actif dans le namespace '$NS' (pid $(cat "$PID_FILE"))"
      exit 0
    fi
    err "le namespace '$NS' existe mais le VPN n'est pas actif : lancez 'ctf-vpn stop' puis relancez 'start'"
    exit 1
  fi

  STARTED=0
  trap on_start_exit EXIT

  detect_uplink
  info "sortie physique : $UPLINK_IF (passerelle $UPLINK_GW)"

  PREV_IP_FORWARD=$(sysctl -n net.ipv4.ip_forward)
  write_state

  info "création du namespace '$NS' et de la paire veth"
  ip netns add "$NS"
  ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
  ip link set "$VETH_NS" netns "$NS"
  ip addr add "$HOST_IP/24" dev "$VETH_HOST"
  ip link set "$VETH_HOST" up
  ip -n "$NS" addr add "$NS_IP/24" dev "$VETH_NS"
  ip -n "$NS" link set "$VETH_NS" up
  ip -n "$NS" link set lo up
  ip -n "$NS" route add default via "$HOST_IP"

  info "routage : le namespace sort par $UPLINK_IF, jamais par WireGuard"
  ip route replace default via "$UPLINK_GW" dev "$UPLINK_IF" table "$RT_TABLE"
  ip rule add from "$SUBNET" lookup "$RT_TABLE" priority "$RULE_PRIO"

  sysctl -qw net.ipv4.ip_forward=1
  iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$UPLINK_IF" -j MASQUERADE
  iptables -A FORWARD -i "$VETH_HOST" -o "$UPLINK_IF" -j ACCEPT
  iptables -A FORWARD -i "$UPLINK_IF" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT

  mkdir -p "$NETNS_ETC"
  printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' >"$NETNS_ETC/resolv.conf"

  info "lancement d'OpenVPN dans le namespace"
  ip netns exec "$NS" openvpn --config "$ovpn" --daemon ctf-vpn \
    --writepid "$PID_FILE" --log "$OVPN_LOG" --verb 3

  if ! wait_vpn; then
    err "OpenVPN n'a pas établi la connexion (voir $OVPN_LOG)"
    exit 1
  fi

  STARTED=1
  info "VPN connecté"
  show_summary
}

show_summary() {
  info "interfaces du namespace :"
  ip -n "$NS" -br addr
  info "route par défaut du namespace :"
  ip -n "$NS" route show default
}

cmd_shell() {
  if ! namespace_exists; then
    err "le namespace '$NS' n'existe pas : lancez 'ctf-vpn start <fichier.ovpn>' d'abord"
    exit 1
  fi
  if [[ -z "${PENTEST_RC:-}" || ! -r "${PENTEST_RC:-}" ]]; then
    err "PENTEST_RC absent : lancez ctf-vpn depuis le devShell (nix develop)"
    exit 1
  fi

  local -a keep=()
  local pair key
  while IFS= read -r -d '' pair; do
    key="${pair%%=*}"
    case "$key" in
      DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_*|DBUS_SESSION_BUS_ADDRESS|SSH_AUTH_SOCK|\
      TERM|LANG|LC_*|QT_*|GTK_*|GDK_*|SDL_*|PENTEST_*|IN_NIX_SHELL|NIX_*)
        keep+=("$pair") ;;
    esac
  done < <(env -0)

  local bash_bin ip_bin setpriv_bin env_bin
  bash_bin=$(PATH="$CALLER_PATH" command -v bash)
  env_bin=$(PATH="$CALLER_PATH" command -v env)
  setpriv_bin=$(PATH="$CALLER_PATH" command -v setpriv)
  ip_bin=$(PATH="$CALLER_PATH" command -v ip)

  exec "$ip_bin" netns exec "$NS" "$setpriv_bin" \
    --reuid="$REAL_UID" --regid="$REAL_GID" --init-groups -- \
    "$env_bin" -i "${keep[@]}" \
      PATH="$CALLER_PATH" HOME="$REAL_HOME" USER="$REAL_USER" LOGNAME="$REAL_USER" \
      CTF_VPN=1 \
    "$bash_bin" --rcfile "$PENTEST_RC" -i
}

cmd_status() {
  if namespace_exists; then
    info "namespace '$NS' : présent"
    show_summary
    if vpn_running; then
      info "OpenVPN : actif (pid $(cat "$PID_FILE"))"
    else
      info "OpenVPN : inactif"
    fi
  else
    info "namespace '$NS' : absent"
  fi
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    info "ip_forward : $(sysctl -n net.ipv4.ip_forward) (précédent : $(. "$STATE_FILE"; echo "${PREV_IP_FORWARD:-?}"))"
  fi
}

cmd_stop() {
  if ! namespace_exists && [[ ! -f "$STATE_FILE" && ! -f "$PID_FILE" ]]; then
    info "rien à nettoyer"
    exit 0
  fi
  teardown
  info "namespace, règles NAT et routage supprimés"
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  shell) cmd_shell ;;
  status) cmd_status ;;
  stop) cmd_stop ;;
  -h|--help|help|"") usage ;;
  *) err "commande inconnue : $1"; usage >&2; exit 1 ;;
esac
