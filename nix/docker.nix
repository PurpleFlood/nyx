# Deterministic Docker image with pentest tools.
# Two profiles: light (~7 GiB) and full (~20-30 GiB).
# Built with dockerTools.buildLayeredImage (no base image).
#
# Build: nix build .#docker-light  or  nix build .#docker-full
# Load:  docker load < result
# Result: image "nyx:light" or "nyx:full"
{
  pkgs,
  pwndbg,
  profile ? "light",
}:
let
  lib = pkgs.lib;
  tools = import ./tools.nix { inherit pkgs pwndbg profile; };

  profileTag = if profile == "full" then "FULL" else "LIGHT";

  # ── RC file: prompt, aliases, utility functions ────────────────────
  rcFile = pkgs.writeText "nyx-rc" ''
    # shellcheck disable=all
    if [[ "''${NYX_VPN:-0}" == "1" ]]; then
      _nyx_tag='[NYX:VPN:${profileTag}]'
    else
      _nyx_tag='[NYX:${profileTag}]'
    fi
    PS1="\[\e[1;35m\]$_nyx_tag\[\e[0m\] \[\e[1;33m\]\u@\h\[\e[0m\]:\w\$ "

    alias ll='ls -la'
    alias la='ls -A'

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
  '';

  # ── Tmux config ────────────────────────────────────────────────────
  tmuxConf = pkgs.writeText "nyx-tmux.conf" ''
    set -g mouse on
    set -g history-limit 50000
    set -g base-index 1
    setw -g pane-base-index 1
    set -g escape-time 10
    set -g default-terminal "tmux-256color"
  '';

  # ── Entrypoint: prepare workspace, start VPN, stay alive ───────────
  entrypoint = pkgs.writeShellApplication {
    name = "nyx-entrypoint";
    runtimeInputs = with pkgs; [
      coreutils
      openvpn
      gnugrep
      bashInteractive
    ];
    text = builtins.readFile ../scripts/nyx-entrypoint.sh;
  };

  # ── fetch-wordlists: download rockyou, SecLists, linpeas ───────────
  fetchWordlists = pkgs.writeShellApplication {
    name = "fetch-wordlists";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gzip
      gnutar
      git
    ];
    text = builtins.readFile ../scripts/fetch-wordlists.sh;
  };

  # All image packages
  allPackages = tools.packages ++ [
    entrypoint
    fetchWordlists
  ];
  toolsPath = lib.makeBinPath allPackages;

in
pkgs.dockerTools.buildLayeredImage {
  name = "nyx";
  tag = profile;
  maxLayers = 120;

  contents = allPackages ++ [
    pkgs.dockerTools.fakeNss # /etc/passwd, /etc/group (root, nobody)
    pkgs.bashInteractive # interactive bash with readline
    pkgs.cacert # CA certificates for curl/wget/git
  ];

  # Directories and config files
  extraCommands = ''
    mkdir -p etc tmp workspace root
    chmod 1777 tmp
    cp ${rcFile} etc/nyx-rc
    cp ${tmuxConf} etc/nyx-tmux.conf
  '';

  config = {
    Cmd = [ "${entrypoint}/bin/nyx-entrypoint" ];
    WorkingDir = "/workspace";
    Env = [
      "PATH=${toolsPath}:/usr/bin:/bin"
      "TERM=xterm-256color"
      "NYX_RC=/etc/nyx-rc"
      "NYX_TMUX_CONF=/etc/nyx-tmux.conf"
      "HOME=/root"
      "NYX_PROFILE=${profile}"
      "_JAVA_AWT_WM_NONREPARENTING=1"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "PENTEST_WORDLISTS=/workspace/wordlists"
      "PENTEST_WORKSPACE=/workspace"
    ];
    Volumes = {
      "/workspace" = { };
    };
  };
}
