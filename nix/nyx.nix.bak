# Empaquette le CLI nyx avec ses dépendances.
# nyx orchestre les conteneurs Docker (start/stop/list/rm).
# Docker doit être installé sur le système hôte.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nyx";
  runtimeInputs = with pkgs; [ coreutils ];
  text = builtins.readFile ../scripts/nyx.sh;
}
