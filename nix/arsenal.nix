# Arsenal (Orange Cyberdefense) : déjà présent dans nixpkgs (1.2.x), on le réexporte ici.
# Si le paquet disparaît de nixpkgs, remplacer cette expression par un
# buildPythonApplication pointant sur github.com/Orange-Cyberdefense/arsenal.
{ pkgs }:
pkgs.arsenal
