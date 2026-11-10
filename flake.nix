{
  # Environnement pentest/CTF isolé : `nix develop` dans ce dépôt, rien n'est exposé hors du devShell.
  # Deux profils disponibles :
  #   nix develop        → profil light (~7 Go)
  #   nix develop .#full → profil full  (~20-30 Go)
  description = "Environnement pentest/CTF isolé";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # pwndbg n'est pas dans nixpkgs : on consomme son flake officiel.
    pwndbg = {
      url = "github:pwndbg/pwndbg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pwndbg, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          # allowUnfree : nécessaire pour burpsuite.
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          mkPentestShell = profile:
            let
              tools = import ./nix/tools.nix { inherit pkgs pwndbg profile; };
              hook = import ./nix/shell-hook.nix {
                inherit pkgs profile;
                toolCount = builtins.length tools.packages;
              };
            in
            pkgs.mkShell {
              packages = tools.packages ++ hook.packages;
              shellHook = hook.shellHook;
            };
        in
        {
          default = mkPentestShell "light";
          full = mkPentestShell "full";
        });
    };
}
