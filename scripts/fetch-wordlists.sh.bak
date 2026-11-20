#!/usr/bin/env bash
# Télécharge les wordlists et outils non packagés dans wordlists/ et tools/.
# Usage : fetch-wordlists.sh <minimal|full>
#   minimal : rockyou.txt.gz uniquement (~15 Mo)
#   full    : rockyou + collection SecLists complète (~1 Go+)
# linpeas est téléchargé dans les deux modes (absent de nixpkgs).
set -euo pipefail

mode="${1:-}"
if [[ "$mode" != "minimal" && "$mode" != "full" ]]; then
  echo "Usage : fetch-wordlists.sh <minimal|full>" >&2
  exit 1
fi

root="${PENTEST_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
wordlists_dir="$root/wordlists"
tools_dir="$root/tools"
mkdir -p "$wordlists_dir" "$tools_dir"

rockyou_url="https://gitlab.com/kalilinux/packages/wordlists/-/raw/kali/master/rockyou.txt.gz"
seclists_url="https://github.com/danielmiessler/SecLists/archive/refs/heads/master.tar.gz"
linpeas_url="https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh"

fetch() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then
    echo "déjà présent : $dest"
    return 0
  fi
  echo "téléchargement : $url"
  curl -fL --retry 3 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

fetch "$rockyou_url" "$wordlists_dir/rockyou.txt.gz"
if [[ ! -s "$wordlists_dir/rockyou.txt" ]]; then
  gunzip -kf "$wordlists_dir/rockyou.txt.gz"
fi

fetch "$linpeas_url" "$tools_dir/linpeas.sh"
chmod +x "$tools_dir/linpeas.sh"

if [[ "$mode" == "full" ]]; then
  seclists_dir="$wordlists_dir/SecLists"
  if [[ -d "$seclists_dir" ]]; then
    echo "SecLists déjà présent : $seclists_dir"
  else
    tmp_tar="$(mktemp "$wordlists_dir/seclists.XXXXXX.tar.gz")"
    trap 'rm -f "$tmp_tar"' EXIT
    fetch "$seclists_url" "$tmp_tar"
    tar -xzf "$tmp_tar" -C "$wordlists_dir"
    mv "$wordlists_dir/SecLists-master" "$seclists_dir"
  fi
fi

echo "terminé (mode $mode) : $wordlists_dir"
