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
  profile,
}:
let
  common = import ./tools/common.nix { inherit pkgs; };
  web = import ./tools/web.nix { inherit pkgs pwndbg; };
  hardware = import ./tools/hardware.nix { inherit pkgs; };
  wireless = import ./tools/wireless.nix { inherit pkgs; };
  dev = import ./tools/dev.nix { inherit pkgs; };

  profileMap = {
    light = common;
    web = common ++ web;
    hardware = common ++ hardware;
    wireless = common ++ wireless;
    dev = common ++ dev;
    full = common ++ web ++ hardware ++ wireless ++ dev;
  };
in
{
  packages = profileMap.${profile};
}
