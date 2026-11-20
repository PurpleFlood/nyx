# DevShell entry point: project scripts in PATH, shared rc file
# (PS1, aliases, functions) and shellHook (banner, variables, workspaces).
# The rc file is also used by `ctf-vpn shell` to inject the environment
# into the network namespace.
{ pkgs, toolCount, profile ? "light" }:
let
  ctfVpn = import ./netns.nix { inherit pkgs; };

  ctfInit = pkgs.writeShellApplication {
    name = "ctf-init";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../scripts/ctf-init.sh;
  };

  fetchWordlists = pkgs.writeShellApplication {
    name = "fetch-wordlists";
    runtimeInputs = with pkgs; [ coreutils curl gzip gnutar git ];
    text = builtins.readFile ../scripts/fetch-wordlists.sh;
  };

  tmuxConf = pkgs.writeText "pentest-tmux.conf" ''
    set -g default-command "${pkgs.bashInteractive}/bin/bash --rcfile ${rcFile} -i"
    set -g mouse on
    set -g history-limit 50000
    set -g base-index 1
    setw -g pane-base-index 1
    set -g escape-time 10
    set -g default-terminal "tmux-256color"
  '';

  ctfTmux = pkgs.writeShellApplication {
    name = "ctf-tmux";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      exec tmux -L pentest -f ${tmuxConf} new-session -A -s "''${1:-ctf}"
    '';
  };

  profileTag = if profile == "full" then "FULL" else "LIGHT";

  rcFile = pkgs.writeText "pentest-rc" ''
    # Pentest environment: prompt, aliases and functions (sourced by devShell and ctf-vpn shell).
    if [[ "''${CTF_VPN:-0}" == 1 ]]; then
      ctf_tag='[CTF:VPN:${profileTag}]'
    else
      ctf_tag='[CTF:${profileTag}]'
    fi
    PS1="\[\e[1;31m\]$ctf_tag\[\e[0m\] \[\e[1;33m\]\u@\h\[\e[0m\]:\w\$ "

    alias ctf-new='ctf-init'
    alias ctf-ls='ls -1 "$PENTEST_WORKSPACE"'

    serve() {
      local port="''${1:-8000}"
      python3 -m http.server "$port"
    }

    listen() {
      if [[ -z "''${1:-}" ]]; then
        echo "usage: listen <port>" >&2
        return 1
      fi
      nc -lvnp "$1"
    }

    ctf-htb() {
      if [[ -z "''${1:-}" ]]; then
        echo "usage: ctf-htb <file.ovpn>" >&2
        return 1
      fi
      ctf-vpn start "$1" && ctf-vpn shell
    }
  '';

  banner = ''
    +--------------------------------------------------+
    |   PENTEST / CTF  -  isolated environment (Nix)   |
    |   Profile: ${if profile == "full" then "FULL (complete arsenal)              " else "LIGHT (essentials)                 "}|
    +--------------------------------------------------+
  '';

  shellHook = ''
    export PENTEST_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    export PENTEST_WORDLISTS="$PENTEST_ROOT/wordlists"
    export PENTEST_WORKSPACE="$HOME/ctf-workspaces"
    export PENTEST_RC="${rcFile}"
    export PENTEST_PROFILE="${profile}"
    mkdir -p "$PENTEST_WORKSPACE" "$PENTEST_WORDLISTS"

    source "$PENTEST_RC"

    cat <<'BANNER'
    ${banner}
    Profile        : ${profile} | Loaded packages: ${toString toolCount} (+ project scripts)
    Quick start    : ctf-new <name> | ctf-htb <file.ovpn> | fetch-wordlists minimal
    Switch profile : nix develop .#full  or  nix develop (light)
    Full help      : see README.md
    BANNER
  '';
in
{
  packages = [ ctfVpn ctfInit fetchWordlists ctfTmux ];
  inherit shellHook;
}
