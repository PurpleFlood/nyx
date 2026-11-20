# Packages scripts/ctf-vpn.sh with its network dependencies.
# writeShellApplication adds set -euo pipefail and runs shellcheck at build.
# sudo is not packaged: uses the host's setuid binary.
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
