# Packages the styx CLI with its dependencies.
# styx manages containerised pentest workspaces (start/stop/list/rm).
# A container runtime (Docker/Podman) must be installed on the host.
{ pkgs }:
pkgs.writeShellApplication {
  name = "styx";
  runtimeInputs = with pkgs; [ coreutils ];
  text = builtins.readFile ../scripts/styx.sh;
}
