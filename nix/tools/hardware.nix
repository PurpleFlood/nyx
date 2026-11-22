{ pkgs }: with pkgs;
[
  # Reverse engineering
  radare2
  ghidra
  binwalk
  strings # from binutils

  # Cracking
  hashcat
  john

  # Firmware
  flashrom
  uefi-firmware-parser

  # Debug
  gdb
  strace
  ltrace
]
