{ pkgs }:
let
  # Firefox with uBlock Origin + FoxyProxy pre-installed via enterprise policies.
  # Dark theme enabled, first-run pages disabled.
  firefoxCustom = pkgs.wrapFirefox pkgs.firefox-unwrapped {
    extraPolicies = {
      # Extensions
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
      # Skip first-run / post-update pages
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      # Dark theme
      Preferences = {
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
      };
    };
  };
in
with pkgs;
[
  # Network
  nmap
  netcat-gnu
  iputils
  dnsutils
  whois
  curl
  wget
  openssh
  socat

  # Utilities
  tmux
  file
  unzip
  p7zip
  jq
  tree
  ripgrep
  fd

  # Browser
  firefoxCustom

  # Wordlists
  seclists
  rockyou # ou ton script fetch-wordlists
]
