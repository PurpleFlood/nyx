# Deterministic Docker image with pentest tools.
# Two profiles: light (~7 GiB) and full (~20-30 GiB).
# Built with dockerTools.buildLayeredImage (no base image).
#
# Build: nix build .#docker-light  or  nix build .#docker-full
# Load:  docker load < result
# Result: image "styx:light" or "styx:full"
{
  pkgs,
  pwndbg,
  profile ? "light",
}:
let
  lib = pkgs.lib;
  tools = import ./tools.nix { inherit pkgs pwndbg profile; };

  profileTag = if profile == "full" then "FULL" else "LIGHT";

  # ── Zsh config: prompt, aliases, utility functions ─────────────────
  zshrcFile = pkgs.writeText "styx-zshrc" ''
    # ── Prompt ───────────────────────────────────────────────────────
    if [[ "''${STYX_VPN:-0}" == "1" ]]; then
      _styx_tag='[STYX:VPN:${profileTag}]'
    else
      _styx_tag='[STYX:${profileTag}]'
    fi
    PS1="%B%F{magenta}$_styx_tag%f%b %B%F{yellow}%n@%m%f%b:%~%# "

    # ── Autosuggestions & syntax highlighting ────────────────────────
    if [[ -f "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
      source "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    fi
    if [[ -f "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
      source "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    fi

    # ── History ──────────────────────────────────────────────────────
    HISTFILE=~/.zsh_history
    HISTSIZE=50000
    SAVEHIST=50000
    setopt SHARE_HISTORY
    setopt HIST_IGNORE_DUPS
    setopt HIST_IGNORE_SPACE

    # ── Completion ───────────────────────────────────────────────────
    autoload -Uz compinit && compinit
    zstyle ':completion:*' menu select

    # ── Aliases ──────────────────────────────────────────────────────
    alias ll='ls -la'
    alias la='ls -A'

    # GUI apps: launch silently in background
    alias firefox='firefox >/dev/null 2>&1 & disown'
    alias burpsuite='burpsuite >/dev/null 2>&1 & disown'
    alias caido='caido-desktop --no-sandbox --disable-gpu >/dev/null 2>&1 & disown'
    alias wireshark='wireshark >/dev/null 2>&1 & disown'
    alias ghidra='ghidra >/dev/null 2>&1 & disown'
    alias zap='zap >/dev/null 2>&1 & disown'

    # ── Functions ────────────────────────────────────────────────────
    serve() {
      local port="''${1:-8000}"
      python3 -m http.server "$port"
    }

    listen() {
      if [[ -z "''${1:-}" ]]; then
        echo "usage: listen <port>" >&2
        return 1
      fi
      pwncat :$1
    }

    listen-nc() {
      if [[ -z "''${1:-}" ]]; then
        echo "usage: listen-nc <port>" >&2
        return 1
      fi
      nc -lvnp "$1"
    }
  '';

  # ── Tmux config ────────────────────────────────────────────────────
  tmuxConf = pkgs.writeText "styx-tmux.conf" ''
    set -g default-shell ${pkgs.zsh}/bin/zsh
    set -g default-command "${pkgs.zsh}/bin/zsh -l"
    set -g mouse on
    set -g history-limit 50000
    set -g base-index 1
    setw -g pane-base-index 1
    set -g escape-time 10
    set -g default-terminal "tmux-256color"
  '';

  # ── Entrypoint: prepare workspace, start VPN, stay alive ───────────
  entrypoint = pkgs.writeShellApplication {
    name = "styx-entrypoint";
    runtimeInputs = with pkgs; [
      coreutils
      openvpn
      gnugrep
      bashInteractive
    ];
    text = builtins.readFile ../scripts/styx-entrypoint.sh;
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
  name = "styx";
  tag = profile;
  maxLayers = 120;

  contents = allPackages ++ [
    pkgs.dockerTools.fakeNss # /etc/passwd, /etc/group (root, nobody)
    pkgs.bashInteractive # interactive bash with readline
    pkgs.zsh             # zsh as default shell
    pkgs.cacert # CA certificates for curl/wget/git
  ];

  # Directories and config files
  extraCommands = ''
    mkdir -p etc tmp workspace root
    chmod 1777 tmp
    cp ${zshrcFile} etc/styx-zshrc
    cp ${tmuxConf} etc/styx-tmux.conf

    # Set zsh as default shell for root in /etc/shells
    echo "${pkgs.zsh}/bin/zsh" >> etc/shells

    # Root .zshrc: source the styx config
    cat > root/.zshrc <<'ZRC'
    [[ -f /etc/styx-zshrc ]] && source /etc/styx-zshrc
ZRC
  '';

  config = {
    Cmd = [ "${entrypoint}/bin/styx-entrypoint" ];
    WorkingDir = "/workspace";
    Env = [
      "PATH=${toolsPath}:/usr/bin:/bin"
      "TERM=xterm-256color"
      "SHELL=${pkgs.zsh}/bin/zsh"
      "ZDOTDIR=/root"
      "STYX_ZSHRC=/etc/styx-zshrc"
      "STYX_TMUX_CONF=/etc/styx-tmux.conf"
      "HOME=/root"
      "STYX_PROFILE=${profile}"
      "_JAVA_AWT_WM_NONREPARENTING=1"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
      "PENTEST_WORDLISTS=/workspace/wordlists"
      "PENTEST_WORKSPACE=/workspace"
    ];
    Volumes = {
      "/workspace" = { };
    };
  };
}
