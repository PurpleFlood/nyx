#!/usr/bin/env bash
# Creates a CTF workspace with scans/, exploits/, loot/, notes/ layout.
# Usage: ctf-init <name>
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: ctf-init <name>" >&2
  exit 1
fi

name="$1"
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "error: invalid name '$name' (letters, digits, '.', '_', '-' only)" >&2
  exit 1
fi

workspace_root="${PENTEST_WORKSPACE:-$HOME/ctf-workspaces}"
target="$workspace_root/$name"

if [[ -e "$target" ]]; then
  echo "workspace already exists: $target"
  exit 0
fi

mkdir -p "$target"/{scans,exploits,loot,notes}
cat >"$target/notes/notes.md" <<EOF
# CTF: $name

- Created: $(date +%F)
- Target(s):
- VPN / namespace: ctf-vpn

## Reconnaissance

## Initial access

## Privilege escalation

## Flags
EOF

echo "workspace created: $target"
