#!/usr/bin/env bash
# Nyx container entrypoint: prepare workspace, start VPN if configured,
# then stay alive to accept shells via `docker exec`.
set -euo pipefail

profile="${NYX_PROFILE:-light}"
name="${NYX_NAME:-workspace}"

ln -sf /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt

# ── Workspace ────────────────────────────────────────────────────────────
for d in scans exploits loot notes; do
  mkdir -p "/workspace/$d"
done

if [[ ! -f "/workspace/notes/notes.md" ]]; then
  cat > /workspace/notes/notes.md <<EOF
# $name

- Date: $(date +%F)
- Profile: $profile

## Reconnaissance

## Initial access

## Privilege escalation

## Flags
EOF
fi

# ── VPN ──────────────────────────────────────────────────────────────────
if [[ "${NYX_VPN:-0}" == "1" ]] && [[ -f "/vpn/config.ovpn" ]]; then
  printf '[nyx] connecting VPN...\n'
  openvpn --config /vpn/config.ovpn --daemon nyx-vpn \
    --writepid /tmp/openvpn.pid --log /tmp/openvpn.log --verb 3

  connected=0
  vpn_wait=60
  while [[ $vpn_wait -gt 0 ]]; do
    if grep -q 'Initialization Sequence Completed' /tmp/openvpn.log 2>/dev/null; then
      printf '[nyx] VPN connected\n'
      connected=1
      break
    fi
    if grep -qE 'AUTH_FAILED|Exiting due to fatal error|Options error' /tmp/openvpn.log 2>/dev/null; then
      printf '[nyx] VPN error:\n' >&2
      tail -5 /tmp/openvpn.log >&2
      break
    fi
    vpn_wait=$((vpn_wait - 1))
    sleep 1
  done
  if [[ $connected -eq 0 ]]; then
    printf '[nyx] warning: VPN not connected after 60s\n' >&2
  fi
fi

# ── Banner ───────────────────────────────────────────────────────────────
tag="LIGHT"
if [[ "$profile" == "full" ]]; then
  tag="FULL"
fi
vpn_info="no"
if [[ "${NYX_VPN:-0}" == "1" ]]; then
  vpn_info="yes"
fi

printf '+--------------------------------------------------+\n'
printf '|   NYX  -  isolated pentest environment (Nix)     |\n'
printf '|   Profile: %-38s|\n' "$tag"
printf '+--------------------------------------------------+\n'
printf '  Workspace : %s\n' "$name"
printf '  VPN       : %s\n' "$vpn_info"
printf '\n'

# Stay alive (shells are opened via `docker exec`)
exec sleep infinity
