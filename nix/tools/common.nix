{ pkgs }:
let
  # Firefox with extensions via enterprise policies.
  firefoxCustom = pkgs.wrapFirefox pkgs.firefox-unwrapped {
    extraPolicies = {
      ExtensionSettings = {
        # uBlock Origin
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };
        # FoxyProxy Standard
        "foxyproxy@eric.h.jung" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/foxyproxy-standard/latest.xpi";
        };
      };
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      Preferences = {
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
      };
    };
  };
in
with pkgs;
[
  # ── Core system utilities ──────────────────────────────────────────
  coreutils
  gnugrep
  gnused
  gawk
  findutils
  ncurses          # clear, tput
  util-linux
  binutils
  xxd

  # ── Shell ──────────────────────────────────────────────────────────
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting

  # ── Network ────────────────────────────────────────────────────────
  nmap
  netcat-gnu
  pwncat           # enhanced netcat (listener)
  iputils
  dnsutils
  whois
  curl
  wget
  openssh
  socat
  openvpn
  iproute2
  iptables

  # ── Utilities ──────────────────────────────────────────────────────
  tmux
  file
  unzip
  p7zip
  jq
  tree
  ripgrep
  fd
  git
  (import ../arsenal.nix { inherit pkgs; })

  # ── Browser ────────────────────────────────────────────────────────
  firefoxCustom

  # ── Wordlists ──────────────────────────────────────────────────────
  seclists
  rockyou
]
