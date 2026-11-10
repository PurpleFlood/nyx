{
  # Environnement pentest/CTF isolé : `nix develop` dans ce dépôt, rien n'est exposé hors du devShell.
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
          tools = import ./nix/tools.nix { inherit pkgs pwndbg; };
          hook = import ./nix/shell-hook.nix {
            inherit pkgs;
            toolCount = builtins.length tools.packages;
          };
        in
        {
          default = pkgs.mkShell {
            packages = tools.packages ++ hook.packages;
            shellHook = hook.shellHook;
          };
        });
    };
}
