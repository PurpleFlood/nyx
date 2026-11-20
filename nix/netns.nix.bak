# Empaquette scripts/ctf-vpn.sh avec ses dépendances réseau (iproute2, iptables, openvpn).
# writeShellApplication ajoute set -euo pipefail et lance shellcheck au build.
# sudo n'est pas empaqueté : on utilise celui du système (setuid NixOS).
{ pkgs }:
pkgs.writeShellApplication {
  name = "ctf-vpn";
  runtimeInputs = with pkgs; [
    iproute2
    iptables
    openvpn
    util-linux
    procps
    coreutils
    gawk
    gnugrep
    getent
  ];
  text = builtins.readFile ../scripts/ctf-vpn.sh;
}
