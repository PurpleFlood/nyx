{ pkgs }: with pkgs;
[
  # Scanners
  burpsuite
  caido-desktop
  nikto
  whatweb

  # Fuzzing
  ffuf
  gobuster
  feroxbuster

  # Injection
  sqlmap
  commix

  # Proxy
  zap

  # Misc
  httpie
  nuclei
]
