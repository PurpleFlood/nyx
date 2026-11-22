{
  # Isolated pentest/CTF environment via Docker/Podman containers.
  #
  # Main usage (containerised):
  #   nix develop          → minimal shell with only the nyx command
  #   nyx install           → build and load the light image
  #   nyx start <name>      → start a containerised workspace
  #
  # Alternative usage (no container):
  #   nix develop .#light  → full devShell, light profile (~7 GiB)
  #   nix develop .#full   → full devShell, full profile  (~20-30 GiB)
  #
  # Direct image builds:
  #   nix build .#docker-light  → Docker image "nyx:light"
  #   nix build .#docker-full   → Docker image "nyx:full"
  description = "Isolated pentest/CTF environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # pwndbg is not in nixpkgs: consumed via its official flake.
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

          # Minimal shell: only the nyx command (fast to build)
          minimalShell = pkgs.mkShell {
            packages = [ nyx ];
            shellHook = ''
              echo ""
              echo "  ☽ nyx — pentest workspace manager"
              echo "  Run 'nyx install' to build an image, then 'nyx start <name>' to begin."
              echo ""
            '';
          };

          # Full shells: all pentest tools (container-free approach)
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
          # nix develop         → minimal shell with nyx only
          # nix develop .#light → full devShell, light profile (no container)
          # nix develop .#full  → full devShell, full profile (no container)
          default = minimalShell;
          light = mkPentestShell "light";
          web = mkPentestShell "web";
          hardware = mkPentestShell "hardware";
          wireless = mkPentestShell "wireless";
          dev = mkPentestShell "dev";
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
          # nyx CLI: containerised workspace manager
          nyx = import ./nix/nyx.nix { inherit pkgs; };

          # Deterministic Docker images built with Nix
          # Usage: nix build .#docker-light && docker load < result
          docker-light = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "light";
          };
          docker-full = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "full";
          };
          docker-web = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "web";
          };
          docker-hardware = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "hardware";
          };
          docker-wireless = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "wireless";
          };
          docker-dev = import ./nix/docker.nix {
            inherit pkgs pwndbg;
            profile = "dev";
          };
        }
      );
    };
}
