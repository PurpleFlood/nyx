{ pkgs }: with pkgs;
[
  # Languages
  python3
  python3Packages.pip
  python3Packages.virtualenv
  nodejs
  go
  rustc
  cargo
  gcc

  # Editors
  neovim

  # Tools
  git
  gh
  gnumake
  cmake
  docker-compose

  # Debug
  gdb
  valgrind
]
