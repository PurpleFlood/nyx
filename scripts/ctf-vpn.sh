#!/usr/bin/env bash
# Manages a CTF VPN (HTB/THM) isolated in a network namespace.
# Namespace traffic exits via the host's physical interface (dedicated routing table),
# never through wg0: the host's WireGuard stays intact.
# Usage: ctf-vpn <start <file.ovpn> | shell | status | stop>
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
warn() { printf '[ctf-vpn] warning: %s\n' "$*" >&2; }
err() { printf '[ctf-vpn] error: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ctf-vpn <command>
  start <file.ovpn>  create namespace and start OpenVPN inside it
  shell               open a shell in the VPN namespace
  status              show namespace and VPN state
  stop                stop OpenVPN and clean up the namespace
EOF
}

# Re-exec as root (network operations) while preserving the environment
# so the namespace shell inherits DISPLAY, PATH, PENTEST_RC, etc.
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

# Detect uplink interface: default route excluding WireGuard, tunnels and veth.
detect_uplink() {
  local line
  line=$(ip -4 route show default | awk '$0 !~ /dev (wg|tun|tap|veth|tailscale)/ { print; exit }') || true
  if [[ -z "$line" ]]; then
    err "no default route outside WireGuard: cannot exit via physical interface"
    return 1
  fi
  UPLINK_GW=$(awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }' <<<"$line")
  UPLINK_IF=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$line")
  if [[ -z "$UPLINK_GW" || -z "$UPLINK_IF" ]]; then
    err "incomplete default route: $line"
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

# Undo everything start may have created; each step tolerates missing resources.
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
    warn "startup failed: cleaning up namespace"
    teardown
  fi
  exit "$rc"
}

cmd_start() {
  local ovpn="${1:-}"
  if [[ -z "$ovpn" ]]; then
    err "missing .ovpn file (ctf-vpn start <file.ovpn>)"
    exit 1
  fi
  if [[ ! -r "$ovpn" ]]; then
    err "file not found or unreadable: $ovpn"
    exit 1
  fi
  ovpn=$(readlink -f "$ovpn")

  if namespace_exists; then
    if vpn_running; then
      info "VPN already active in namespace '$NS' (pid $(cat "$PID_FILE"))"
      exit 0
    fi
    err "namespace '$NS' exists but VPN is not running: run 'ctf-vpn stop' then restart"
    exit 1
  fi

  STARTED=0
  trap on_start_exit EXIT

  detect_uplink
  info "physical uplink: $UPLINK_IF (gateway $UPLINK_GW)"

  PREV_IP_FORWARD=$(sysctl -n net.ipv4.ip_forward)
  write_state

  info "creating namespace '$NS' and veth pair"
  ip netns add "$NS"
  ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
  ip link set "$VETH_NS" netns "$NS"
  ip addr add "$HOST_IP/24" dev "$VETH_HOST"
  ip link set "$VETH_HOST" up
  ip -n "$NS" addr add "$NS_IP/24" dev "$VETH_NS"
  ip -n "$NS" link set "$VETH_NS" up
  ip -n "$NS" link set lo up
  ip -n "$NS" route add default via "$HOST_IP"

  info "routing: namespace exits via $UPLINK_IF, never through WireGuard"
  ip route replace default via "$UPLINK_GW" dev "$UPLINK_IF" table "$RT_TABLE"
  ip rule add from "$SUBNET" lookup "$RT_TABLE" priority "$RULE_PRIO"

  sysctl -qw net.ipv4.ip_forward=1
  iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$UPLINK_IF" -j MASQUERADE
  iptables -A FORWARD -i "$VETH_HOST" -o "$UPLINK_IF" -j ACCEPT
  iptables -A FORWARD -i "$UPLINK_IF" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT

  mkdir -p "$NETNS_ETC"
  printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' >"$NETNS_ETC/resolv.conf"

  info "starting OpenVPN in the namespace"
  ip netns exec "$NS" openvpn --config "$ovpn" --daemon ctf-vpn \
    --writepid "$PID_FILE" --log "$OVPN_LOG" --verb 3

  if ! wait_vpn; then
    err "OpenVPN failed to connect (see $OVPN_LOG)"
    exit 1
  fi

  STARTED=1
  info "VPN connected"
  show_summary
}

show_summary() {
  info "namespace interfaces:"
  ip -n "$NS" -br addr
  info "namespace default route:"
  ip -n "$NS" route show default
}

cmd_shell() {
  if ! namespace_exists; then
    err "namespace '$NS' does not exist: run 'ctf-vpn start <file.ovpn>' first"
    exit 1
  fi
  if [[ -z "${PENTEST_RC:-}" || ! -r "${PENTEST_RC:-}" ]]; then
    err "PENTEST_RC not set: run ctf-vpn from the devShell (nix develop)"
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
    info "namespace '$NS': present"
    show_summary
    if vpn_running; then
      info "OpenVPN: active (pid $(cat "$PID_FILE"))"
    else
      info "OpenVPN: inactive"
    fi
  else
    info "namespace '$NS': absent"
  fi
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    info "ip_forward: $(sysctl -n net.ipv4.ip_forward) (previous: $(. "$STATE_FILE"; echo "${PREV_IP_FORWARD:-?}"))"
  fi
}

cmd_stop() {
  if ! namespace_exists && [[ ! -f "$STATE_FILE" && ! -f "$PID_FILE" ]]; then
    info "nothing to clean up"
    exit 0
  fi
  teardown
  info "namespace, NAT rules and routing cleaned up"
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  shell) cmd_shell ;;
  status) cmd_status ;;
  stop) cmd_stop ;;
  -h|--help|help|"") usage ;;
  *) err "unknown command: $1"; usage >&2; exit 1 ;;
esac
