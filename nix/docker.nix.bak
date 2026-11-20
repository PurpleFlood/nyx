# Construit une image Docker déterministe avec les outils de pentest.
# Deux profils : light (~7 Go d'outils) et full (~20-30 Go).
# L'image est construite avec dockerTools.buildLayeredImage (pas de base image).
#
# Construction : nix build .#docker-light  ou  nix build .#docker-full
# Chargement :   docker load < result
# Résultat :     image "nyx:light" ou "nyx:full" dans Docker
{
  pkgs,
  pwndbg,
  profile ? "light",
}:
let
  lib = pkgs.lib;
  tools = import ./tools.nix { inherit pkgs pwndbg profile; };

  profileTag = if profile == "full" then "FULL" else "LIGHT";

  # ── RC file : prompt, aliases, fonctions utilitaires ────────────────
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
        echo "usage : listen <port>" >&2
        return 1
      fi
      nc -lvnp "$1"
    }
  '';

  # ── Configuration tmux ─────────────────────────────────────────────
  tmuxConf = pkgs.writeText "nyx-tmux.conf" ''
    set -g mouse on
    set -g history-limit 50000
    set -g base-index 1
    setw -g pane-base-index 1
    set -g escape-time 10
    set -g default-terminal "tmux-256color"
  '';

  # ── Entrypoint : prépare le workspace, lance le VPN, reste actif ──
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

  # ── fetch-wordlists : télécharge rockyou, SecLists, linpeas ────────
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

  # Tous les paquets de l'image
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
    pkgs.bashInteractive # bash interactif avec readline
    pkgs.cacert # certificats CA pour curl/wget/git
  ];

  # Répertoires et fichiers de configuration
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
