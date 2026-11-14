#!/usr/bin/env bash
# Entrypoint du conteneur nyx : prépare le workspace, démarre le VPN si configuré,
# puis reste actif pour accepter des shells via `docker exec`.
set -euo pipefail

profile="${NYX_PROFILE:-light}"
name="${NYX_NAME:-workspace}"

# ── Workspace ────────────────────────────────────────────────────────────
for d in scans exploits loot notes; do
  mkdir -p "/workspace/$d"
done

if [[ ! -f "/workspace/notes/notes.md" ]]; then
  cat > /workspace/notes/notes.md <<EOF
# $name

- Date : $(date +%F)
- Profil : $profile

## Reconnaissance

## Accès initial

## Escalade de privilèges

## Flags
EOF
fi

# ── VPN ──────────────────────────────────────────────────────────────────
if [[ "${NYX_VPN:-0}" == "1" ]] && [[ -f "/vpn/config.ovpn" ]]; then
  printf '[nyx] connexion VPN en cours...\n'
  openvpn --config /vpn/config.ovpn --daemon nyx-vpn \
    --writepid /tmp/openvpn.pid --log /tmp/openvpn.log --verb 3

  connected=0
  vpn_wait=60
  while [[ $vpn_wait -gt 0 ]]; do
    if grep -q 'Initialization Sequence Completed' /tmp/openvpn.log 2>/dev/null; then
      printf '[nyx] VPN connecté\n'
      connected=1
      break
    fi
    if grep -qE 'AUTH_FAILED|Exiting due to fatal error|Options error' /tmp/openvpn.log 2>/dev/null; then
      printf '[nyx] erreur VPN :\n' >&2
      tail -5 /tmp/openvpn.log >&2
      break
    fi
    vpn_wait=$((vpn_wait - 1))
    sleep 1
  done
  if [[ $connected -eq 0 ]]; then
    printf '[nyx] avertissement : VPN non connecté après 60s\n' >&2
  fi
fi

# ── Bannière ─────────────────────────────────────────────────────────────
tag="LIGHT"
if [[ "$profile" == "full" ]]; then
  tag="FULL"
fi
vpn_info="non"
if [[ "${NYX_VPN:-0}" == "1" ]]; then
  vpn_info="oui"
fi

printf '+--------------------------------------------------+\n'
printf '|   NYX  -  environnement pentest isolé (Nix)      |\n'
printf '|   Profil : %-39s|\n' "$tag"
printf '+--------------------------------------------------+\n'
printf '  Workspace : %s\n' "$name"
printf '  VPN       : %s\n' "$vpn_info"
printf '\n'

# Reste actif (les shells sont ouverts via `docker exec`)
exec sleep infinity
