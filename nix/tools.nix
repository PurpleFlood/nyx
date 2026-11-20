# Liste des outils du devShell, organisée par phase de pentest.
# Deux profils disponibles :
#   - "light" (~7 Go) : 2-3 outils par phase, suffisant pour la plupart des CTF.
#   - "full"  (~20-30 Go) : arsenal complet avec outils avancés par phase.
#
# Choix documentés :
#  - smbclient : absent comme attribut, fourni par le paquet `samba`.
#  - ncat : absent de nixpkgs, fourni par `nmap` (binaire ncat/nping inclus).
#  - linpeas : absent de nixpkgs, téléchargé par scripts/fetch-wordlists.sh.
#  - pwndbg : pas dans nixpkgs, consommé via l'input flake officiel pwndbg/pwndbg.
#  - hashid : préféré à hash-identifier (Python 3, identification plus à jour).
#  - snmpcheck : outil SNMP d'énumération ; net-snmp apporte snmpwalk/snmpget (requêtes brutes).
#  - Les paquets non disponibles sur la plateforme courante sont filtrés (ex. burpsuite hors x86_64).
#  - Firefox : livré avec uBlock Origin pré-installé via les policies entreprise Mozilla.
{
  pkgs,
  pwndbg,
  profile ? "light",
}:
let
  lib = pkgs.lib;
  isFull = profile == "full";

  # Firefox avec uBlock Origin installé via les enterprise policies.
  # L'extension est automatiquement téléchargée et activée au premier lancement.
  firefoxWithUblock = pkgs.wrapFirefox pkgs.firefox-unwrapped {
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
      # Pas d'écran de bienvenue / config au premier lancement
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      # Thème dark
      Preferences = {
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
      };
    };
  };

  pythonTools = pkgs.python3.withPackages (
    ps:
    [
      ps.requests
      ps.beautifulsoup4
      ps.pycryptodome
      ps.pwntools
    ]
    ++ lib.optionals isFull [
      ps.impacket
      ps.scapy
    ]
  );

  # ──────────────────────────────────────────────
  # Groupes de base (profil light)
  # ──────────────────────────────────────────────
  groups = {
    # Phase 1 : reconnaissance passive (OSINT)
    recon = with pkgs; [
      whois
      theharvester
      dnsrecon
    ];

    # Phase 2 : scan et énumération
    scanning = with pkgs; [
      nmap
      masscan
      enum4linux-ng
      samba
      snmpcheck
      net-snmp
    ];

    # Phase 3 : analyse web
    web = with pkgs; [
      gobuster
      ffuf
      nikto
      burpsuite
      sqlmap
      whatweb
      firefoxCustom
    ];

    # Phase 4 : exploitation
    exploitation = with pkgs; [
      metasploit
      exploitdb
      netexec
    ];

    # Phase 5 : attaques de mots de passe
    # thc-hydra : `hydra` de nixpkgs désigne Hydra, le CI de Nix.
    passwords = with pkgs; [
      john
      hashcat
      thc-hydra
      hashid
    ];

    # Phase 6 : post-exploitation et privesc
    postexploit = with pkgs; [
      pspy
      chisel
    ];

    # Phase 7 : réseau et sniffing
    network = with pkgs; [
      wireshark
      tcpdump
      netcat-gnu
      socat
    ];

    # Phase 8 : reverse engineering et pwn
    reverse = [
      pkgs.ghidra
      pkgs.radare2
      pkgs.gdb
      pwndbg.packages.${pkgs.stdenv.hostPlatform.system}.default
      pythonTools
    ];

    # Phase 9 : forensics et stéganographie
    forensics = with pkgs; [
      binwalk
      steghide
      exiftool
      foremost
    ];

    # Phase 10 : utilitaires transversaux
    utils = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      findutils
      ncurses # pour clear, tput
      curl
      wget
      jq
      git
      (import ./arsenal.nix { inherit pkgs; })
      openvpn
      tmux
      file
      binutils
      xxd
      iproute2
      iptables
      util-linux
      zsh
      zsh-autosuggestions
      zsh-syntax-highlighting
    ];
  };

  # ──────────────────────────────────────────────
  # Groupes supplémentaires (profil full uniquement)
  # ──────────────────────────────────────────────
  extraGroups = lib.optionalAttrs isFull {
    # Phase 1 : reconnaissance étendue
    # amass : énumération de sous-domaines (actif + passif, large base de sources).
    # subfinder : découverte rapide de sous-domaines via des sources passives.
    recon-extra = with pkgs; [
      amass
      subfinder
    ];

    # Phase 2 : scan avancé
    # rustscan : scanner de ports ultra-rapide, passe le relais à nmap pour le détail.
    scanning-extra = with pkgs; [ rustscan ];

    # Phase 3 : analyse web avancée
    # feroxbuster : brute-force récursif de répertoires (Rust, rapide).
    # nuclei : scanner de vulnérabilités basé sur des templates YAML.
    # wpscan : scanner dédié WordPress (thèmes, plugins, utilisateurs).
    # zap : proxy d'interception alternatif à Burp Suite (OWASP, open source).
    web-extra = with pkgs; [
      feroxbuster
      nuclei
      wpscan
      zap
      jdk17
    ];

    # Phase 5 : mots de passe avancés
    # crunch : générateur de wordlists personnalisées (patterns, charsets).
    # hcxtools : capture et conversion de handshakes Wi-Fi (WPA/WPA2).
    passwords-extra = with pkgs; [
      crunch
      hcxtools
    ];

    # Phase 7 : réseau avancé
    # ettercap : attaques MITM sur LAN (ARP spoofing, sniffing).
    # ngrep : grep réseau en temps réel sur le trafic (pattern matching).
    # proxychains-ng : force le trafic d'un programme à passer par des proxys (SOCKS/HTTP).
    network-extra = with pkgs; [
      ettercap
      ngrep
      proxychains-ng
    ];

    # Phase 8 : reverse engineering avancé
    # rizin : fork de radare2, API modernisée (alternative/complément).
    # jadx : décompilateur Java/Android (APK → source lisible).
    # yara : moteur de pattern matching pour la détection de malware et le triage.
    reverse-extra = with pkgs; [
      rizin
      jadx
      yara
    ];

    # Phase 9 : forensics avancé
    # sleuthkit : analyse de systèmes de fichiers (images disque, partitions).
    # testdisk : récupération de partitions et fichiers supprimés.
    forensics-extra = with pkgs; [
      sleuthkit
      testdisk
    ];

    # Phase 10 : utilitaires supplémentaires
    # rlwrap : readline wrapper pour les programmes sans historique (nc, etc.).
    # p7zip : compression/décompression 7z et formats variés.
    # unzip : extraction d'archives ZIP.
    # dos2unix : conversion de fins de ligne (utile pour les fichiers transférés).
    utils-extra = with pkgs; [
      rlwrap
      p7zip
      unzip
      dos2unix
    ];
  };

  allGroups = groups // extraGroups;
  allPackages = lib.concatLists (lib.attrValues allGroups);
in
{
  inherit groups extraGroups;
  # Filtre les paquets dont la plateforme n'est pas supportée (ex. burpsuite sur aarch64).
  packages = lib.filter (p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) allPackages;
}
