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

  # Proxy / browser
  firefox # avec tes extensions
  zaproxy

  # Misc
  httpie
  nuclei
]
