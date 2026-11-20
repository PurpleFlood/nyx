# Pentest tools organised by methodology phase.
# Two profiles:
#   - "light" (~7 GiB): 2-3 tools per phase, enough for most CTFs.
#   - "full"  (~20-30 GiB): complete arsenal with advanced tools.
#
# Notable choices:
#  - smbclient: provided by the `samba` package.
#  - ncat: provided by `nmap` (includes ncat/nping).
#  - linpeas: not in nixpkgs, downloaded by scripts/fetch-wordlists.sh.
#  - pwndbg: not in nixpkgs, consumed via the official pwndbg/pwndbg flake input.
#  - hashid: preferred over hash-identifier (Python 3, more up-to-date).
#  - snmpcheck: SNMP enumeration tool; net-snmp provides snmpwalk/snmpget (raw queries).
#  - Platform-unsupported packages are filtered out (e.g. burpsuite outside x86_64).
#  - Firefox: shipped with uBlock Origin and FoxyProxy pre-installed via enterprise policies.
{
  pkgs,
  pwndbg,
  profile ? "light",
}:
let
  lib = pkgs.lib;
  isFull = profile == "full";

  # Firefox with extensions via enterprise policies.
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
  # Base groups (light profile)
  # ──────────────────────────────────────────────
  groups = {
    # Phase 1: passive recon (OSINT)
    recon = with pkgs; [
      whois
      theharvester
      dnsrecon
    ];

    # Phase 2: scanning & enumeration
    scanning = with pkgs; [
      nmap
      masscan
      enum4linux-ng
      samba
      snmpcheck
      net-snmp
    ];

    # Phase 3: web analysis
    web = with pkgs; [
      gobuster
      ffuf
      nikto
      burpsuite
      sqlmap
      whatweb
      firefoxCustom
    ];

    # Phase 4: exploitation
    exploitation = with pkgs; [
      metasploit
      exploitdb
      netexec
    ];

    # Phase 5: password attacks
    # thc-hydra: `hydra` in nixpkgs refers to Nix CI, not THC-Hydra.
    passwords = with pkgs; [
      john
      hashcat
      thc-hydra
      hashid
    ];

    # Phase 6: post-exploitation & privesc
    postexploit = with pkgs; [
      pspy
      chisel
    ];

    # Phase 7: network & sniffing
    network = with pkgs; [
      wireshark
      tcpdump
      netcat-gnu
      socat
    ];

    # Phase 8: reverse engineering & pwn
    reverse = [
      pkgs.ghidra
      pkgs.radare2
      pkgs.gdb
      pwndbg.packages.${pkgs.stdenv.hostPlatform.system}.default
      pythonTools
    ];

    # Phase 9: forensics & steganography
    forensics = with pkgs; [
      binwalk
      steghide
      exiftool
      foremost
    ];

    # Phase 10: cross-cutting utilities
    utils = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      findutils
      ncurses # clear, tput
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
  # Extra groups (full profile only)
  # ──────────────────────────────────────────────
  extraGroups = lib.optionalAttrs isFull {
    # Phase 1: extended recon
    recon-extra = with pkgs; [
      amass       # subdomain enumeration (active + passive)
      subfinder   # fast passive subdomain discovery
    ];

    # Phase 2: advanced scanning
    scanning-extra = with pkgs; [
      rustscan    # ultra-fast port scanner, hands off to nmap
    ];

    # Phase 3: advanced web analysis
    web-extra = with pkgs; [
      feroxbuster # recursive directory brute-forcing (Rust)
      nuclei      # template-based vulnerability scanner
      wpscan      # WordPress scanner
      zap         # OWASP ZAP intercepting proxy
      jdk17
    ];

    # Phase 5: advanced password attacks
    passwords-extra = with pkgs; [
      crunch      # custom wordlist generator
      hcxtools    # Wi-Fi handshake capture/conversion
    ];

    # Phase 7: advanced network
    network-extra = with pkgs; [
      ettercap       # MITM attacks (ARP spoofing, sniffing)
      ngrep          # real-time network grep
      proxychains-ng # force traffic through SOCKS/HTTP proxies
    ];

    # Phase 8: advanced reverse engineering
    reverse-extra = with pkgs; [
      rizin  # radare2 fork, modernised API
      jadx   # Java/Android decompiler (APK → source)
      yara   # pattern matching for malware detection
    ];

    # Phase 9: advanced forensics
    forensics-extra = with pkgs; [
      sleuthkit  # filesystem analysis (disk images, partitions)
      testdisk   # partition and file recovery
    ];

    # Phase 10: extra utilities
    utils-extra = with pkgs; [
      rlwrap    # readline wrapper for programs without history
      p7zip     # 7z compression/decompression
      unzip     # ZIP extraction
      dos2unix  # line ending conversion
    ];
  };

  allGroups = groups // extraGroups;
  allPackages = lib.concatLists (lib.attrValues allGroups);
in
{
  inherit groups extraGroups;
  # Filter out packages unsupported on the current platform (e.g. burpsuite on aarch64).
  packages = lib.filter (p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) allPackages;
}
