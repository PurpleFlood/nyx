{ pkgs }: with pkgs;
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

  # Wordlists
  seclists
  rockyou # ou ton script fetch-wordlists
]
