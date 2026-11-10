# Liste des outils du devShell, organisée par phase de pentest.
# Choix documentés :
#  - smbclient : absent comme attribut, fourni par le paquet `samba`.
#  - ncat : absent de nixpkgs, fourni par `nmap` (binaire ncat/nping inclus).
#  - linpeas : absent de nixpkgs, téléchargé par scripts/fetch-wordlists.sh.
#  - pwndbg : pas dans nixpkgs, consommé via l'input flake officiel pwndbg/pwndbg.
#  - hashid : préféré à hash-identifier (Python 3, identification plus à jour).
#  - snmpcheck : outil SNMP d'énumération ; net-snmp apporte snmpwalk/snmpget (requêtes brutes).
#  - Les paquets non disponibles sur la plateforme courante sont filtrés (ex. burpsuite hors x86_64).
{ pkgs, pwndbg }:
let
  lib = pkgs.lib;
  pythonTools = pkgs.python3.withPackages (ps: [
    ps.requests
    ps.beautifulsoup4
    ps.pycryptodome
    ps.pwntools
  ]);

  groups = {
    # Phase 1 : reconnaissance passive (OSINT)
    recon = with pkgs; [ whois theharvester dnsrecon ];

    # Phase 2 : scan et énumération
    scanning = with pkgs; [ nmap masscan enum4linux-ng samba snmpcheck net-snmp ];

    # Phase 3 : analyse web
    web = with pkgs; [ gobuster ffuf nikto burpsuite sqlmap whatweb ];

    # Phase 4 : exploitation
    exploitation = with pkgs; [ metasploit exploitdb netexec ];

    # Phase 5 : attaques de mots de passe
    # thc-hydra : `hydra` de nixpkgs désigne Hydra, le CI de Nix.
    passwords = with pkgs; [ john hashcat thc-hydra hashid ];

    # Phase 6 : post-exploitation et privesc
    postexploit = with pkgs; [ pspy chisel ];

    # Phase 7 : réseau et sniffing
    network = with pkgs; [ wireshark tcpdump netcat-gnu socat ];

    # Phase 8 : reverse engineering et pwn
    reverse = [ pkgs.ghidra pkgs.radare2 pkgs.gdb pwndbg.packages.${pkgs.stdenv.hostPlatform.system}.default pythonTools ];

    # Phase 9 : forensics et stéganographie
    forensics = with pkgs; [ binwalk steghide exiftool foremost ];

    # Phase 10 : utilitaires transversaux
    utils = with pkgs; [
      curl wget jq git
      (import ./arsenal.nix { inherit pkgs; })
      openvpn tmux
      file binutils xxd
      iproute2 iptables util-linux
    ];
  };

  allPackages = lib.concatLists (lib.attrValues groups);
in
{
  inherit groups;
  # Filtre les paquets dont la plateforme n'est pas supportée (ex. burpsuite sur aarch64).
  packages = lib.filter (p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) allPackages;
}
