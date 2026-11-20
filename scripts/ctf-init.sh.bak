#!/usr/bin/env bash
# Crée un workspace CTF avec l'arborescence scans/, exploits/, loot/, notes/.
# Usage : ctf-init <nom>
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage : ctf-init <nom>" >&2
  exit 1
fi

name="$1"
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "erreur : nom invalide '$name' (lettres, chiffres, '.', '_', '-' uniquement)" >&2
  exit 1
fi

workspace_root="${PENTEST_WORKSPACE:-$HOME/ctf-workspaces}"
target="$workspace_root/$name"

if [[ -e "$target" ]]; then
  echo "workspace déjà existant : $target"
  exit 0
fi

mkdir -p "$target"/{scans,exploits,loot,notes}
cat >"$target/notes/notes.md" <<EOF
# CTF : $name

- Date de création : $(date +%F)
- Cible(s) :
- VPN / namespace : ctf-vpn

## Reconnaissance

## Accès initial

## Escalade de privilèges

## Flags
EOF

echo "workspace créé : $target"
