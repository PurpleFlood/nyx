{
  # Environnement pentest/CTF isolé via conteneurs Docker/Podman.
  #
  # Usage principal (conteneurisé) :
  #   nix develop          → shell minimal avec uniquement la commande nyx
  #   nyx install           → construit et charge l'image light
  #   nyx start <nom>       → lance un workspace conteneurisé
  #
  # Usage alternatif (sans conteneur) :
  #   nix develop .#light  → devShell complet profil light (~7 Go)
  #   nix develop .#full   → devShell complet profil full  (~20-30 Go)
  #
  # Construction directe des images :
  #   nix build .#docker-light  → image Docker "nyx:light"
  #   nix build .#docker-full   → image Docker "nyx:full"
  description = "Environnement pentest/CTF isolé";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # pwndbg n'est pas dans nixpkgs : on consomme son flake officiel.
    pwndbg = {
      url = "github:pwndbg/pwndbg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pwndbg,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      # ── DevShells ─────────────────────────────────────────────────────
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          nyx = import ./nix/nyx.nix { inherit pkgs; };

          # Shell minimal : uniquement la commande nyx (rapide à construire)
          minimalShell = pkgs.mkShell {
            packages = [ nyx ];
            shellHook = ''
              echo ""
              echo "  ☽ nyx — pentest workspace manager"
              echo "  Run 'nyx install' to build an image, then 'nyx start <name>' to begin."
              echo ""
            '';
          };

          # Shells complets : tous les outils pentest (approche sans conteneur)
          mkPentestShell =
            profile:
            let
              tools = import ./nix/tools.nix { inherit pkgs pwndbg profile; };
              hook = import ./nix/shell-hook.nix {
                inherit pkgs profile;
                toolCount = builtins.length tools.packages;
              };
            in
            pkgs.mkShell {
              packages = tools.packages ++ hook.packages ++ [ nyx ];
              shellHook = hook.shellHook;
            };
        in
        {
          # nix develop         → shell minimal avec nyx uniquement
          # nix develop .#light → devShell complet profil light (sans conteneur)
          # nix develop .#full  → devShell complet profil full (sans conteneur)
          default = minimalShell;
          light = mkPentestShell "light";
          full = mkPentestShell "full";
        }
      );

      # ── Packages ────────────────────────────────────────────────────
      packages = forAllSystems (
        system:
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
        }
      );
    };
}
