# Packages the nyx CLI with its dependencies.
# nyx manages containerised pentest workspaces (start/stop/list/rm).
# A container runtime (Docker/Podman) must be installed on the host.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nyx";
  runtimeInputs = with pkgs; [ coreutils ];
  text = builtins.readFile ../scripts/nyx.sh;
}
