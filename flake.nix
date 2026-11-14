{
  # Environnement pentest/CTF isolé : `nix develop` dans ce dépôt, rien n'est exposé hors du devShell.
  # Deux profils disponibles :
  #   nix develop        → profil light (~7 Go)
  #   nix develop .#full → profil full  (~20-30 Go)
  #
  # Conteneurisation Docker (branche nix-container) :
  #   nix build .#docker-light  → image Docker "nyx:light"
  #   nix build .#docker-full   → image Docker "nyx:full"
  #   docker load < result      → charge l'image dans Docker
  #   nyx start <nom>           → lance un workspace conteneurisé
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
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # ── DevShells (approche classique sans conteneur) ───────────────
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          mkPentestShell = profile:
            let
              tools = import ./nix/tools.nix { inherit pkgs pwndbg profile; };
              hook = import ./nix/shell-hook.nix {
                inherit pkgs profile;
                toolCount = builtins.length tools.packages;
              };
              nyx = import ./nix/nyx.nix { inherit pkgs; };
            in
            pkgs.mkShell {
              packages = tools.packages ++ hook.packages ++ [ nyx ];
              shellHook = hook.shellHook;
            };
        in
        {
          default = mkPentestShell "light";
          full = mkPentestShell "full";
        });

      # ── Packages ────────────────────────────────────────────────────
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          # CLI nyx : gestionnaire de workspaces conteneurisés
          nyx = import ./nix/nyx.nix { inherit pkgs; };

          # Images Docker construites avec Nix (déterministes)
          # Usage : nix build .#docker-light && docker load < result
          docker-light = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "light";
          };
          docker-full = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "full";
          };
        });
    };
}
