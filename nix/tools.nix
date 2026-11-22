{
  pkgs,
  pwndbg,
  profile,
}:
let
  common = import ./tools/common.nix { inherit pkgs; };
  web = import ./tools/web.nix { inherit pkgs; };
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
