# pentest-env

A portable penetration testing and CTF environment built with Nix. The `nyx` CLI manages containerised workspaces (Docker or Podman) that carry every tool you need. When you stop a workspace, nothing is left on your host system.

An alternative `nix develop` mode is also available for a lighter, non-containerised workflow (see section 11).

## 1. Overview

- Tools grouped by pentest methodology phase (OSINT → scanning → web → exploitation → passwords → post-exploitation → network → reverse engineering → forensics → utilities).
- **Two profiles**: `light` (~7 GiB, 2-3 tools per phase) and `full` (~20-30 GiB, extended arsenal with advanced tools).
- **Container-based isolation**: each workspace runs in its own Docker/Podman container with full tool access.
- **VPN support**: mount an `.ovpn` file and the container starts OpenVPN automatically.
- Firefox pre-configured with uBlock Origin via enterprise policies.
- Graphical applications (Burp Suite, Wireshark, Ghidra, Firefox) forwarded from the container to the host display server.
- Cross-platform: works on Linux, macOS and Windows (via Docker Desktop or Podman).

## 2. Prerequisites

### Nix

Nix is required to **build** the container images. It is not needed to **run** them.

- **NixOS**: flakes enabled in your system configuration:

  ```nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  ```

- **Other distributions** (Ubuntu, Debian, Fedora, Arch, macOS, ...):

  Install Nix with the Determinate Systems installer (enables flakes by default):

  ```bash
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  ```

  Or the official installer:

  ```bash
  sh <(curl -L https://nixos.org/nix/install) --daemon
  ```

  If you used the official installer, enable flakes by adding `experimental-features = nix-command flakes` to `/etc/nix/nix.conf` and restart the daemon.

### Container runtime

One of:

- **Podman** (recommended, rootless, OCI-native): `podman --version`
- **Docker**: `docker --version`

`nyx` auto-detects the available runtime, with Podman taking priority. You can force a runtime with `NYX_RUNTIME=docker` or `NYX_RUNTIME=podman`.

### Disk space

- **Light profile**: about **3.2 GiB to download** and **7 GiB** for the container image.
- **Full profile**: about **10-15 GiB to download** and **20-30 GiB** for the container image.
- Plus wordlists if downloaded inside a workspace (`minimal` ≈ 15 MB, `full` ≈ 1 GB+ for SecLists).

## 3. Quick start

```bash
# Clone and enter the repository
git clone <repository-url> pentest-env
cd pentest-env

# Enter the minimal shell (only provides the nyx command, builds in seconds)
nix develop

# Build and load the light image
nyx install

# Start a workspace
nyx start my-first-ctf

# You're now inside the container with all pentest tools available
nmap 10.10.10.x
```

`nix develop` only installs the `nyx` CLI itself, not the pentest tools. The tools live inside the container image, built by `nyx install`.

## 4. Image management

### Build and load an image

```bash
nyx install              # build and load the light image (default)
nyx install light        # same as above
nyx install full         # build and load the full image
```

`nyx install` uses `nix build` to produce a deterministic OCI image via `dockerTools.buildLayeredImage`, then loads it into your container runtime with `docker load` or `podman load`.

If you are not inside the repository, `nyx` fetches the flake from GitHub automatically.

### Remove an image

```bash
nyx uninstall light      # remove the light image
nyx uninstall full       # remove the full image
```

`nyx uninstall` refuses to remove an image that has active workspaces. Stop them first.

### List images

```bash
nyx images               # show installed nyx images with size and status
```

## 5. Workspace management

A workspace is a named container with a persistent directory at `~/nyx-workspace/<name>/`.

### Start or enter a workspace

```bash
nyx start <name>                        # start with light profile (default)
nyx start <name> --profile full         # start with full profile
nyx start <name> --vpn ~/lab.ovpn       # start with VPN
nyx start <name> --profile full --vpn ~/lab.ovpn  # full + VPN
```

If the workspace already exists and is running, `nyx start` opens a new shell into it. If the required image is not installed, `nyx` proposes to build and load it for you.

### List workspaces

```bash
nyx list                 # show all workspaces with status, profile and uptime
```

### Stop a workspace

```bash
nyx stop <name>          # stop a running workspace (data is kept)
```

### Remove a workspace

```bash
nyx rm <name>            # remove a stopped workspace and its local directory
```

A running workspace must be stopped before it can be removed.

## 6. Workspace layout

When a workspace starts for the first time, the following directories are created in `~/nyx-workspace/<name>/`:

```
scans/       # nmap, masscan, gobuster… output
exploits/    # scripts and PoCs
loot/        # retrieved files (user.txt, root.txt, creds…)
notes/       # notes.md with a report template
```

The `notes/notes.md` file contains a pre-filled template with sections for target info, reconnaissance, exploitation, flags and lessons learned.

## 7. VPN support

```bash
nyx start htb-box --vpn ~/Downloads/lab.ovpn
```

The `.ovpn` file is mounted into the container. OpenVPN starts automatically inside the container and waits up to 60 seconds for the connection to establish. The container prompt shows `[NYX:VPN:LIGHT]` or `[NYX:VPN:FULL]` when the VPN is active.

The VPN runs entirely inside the container and does not affect the host's network configuration: your WireGuard or other VPN on the host keeps working normally.

The container is started with `--cap-add=NET_ADMIN` and `--device=/dev/net/tun` to allow OpenVPN to create the tun device.

## 8. GUI applications

The container forwards graphical applications (Burp Suite, Wireshark, Ghidra, Firefox) to the host display server. Both X11 and Wayland are supported:

- **X11**: the `DISPLAY` variable and `/tmp/.X11-unix` socket are forwarded.
- **Wayland**: `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` are forwarded.

On non-NixOS distributions, GUI applications from the container may need [nixGL](https://github.com/nix-community/nixGL) for OpenGL support.

## 9. Tools by phase

Tool choices follow the project rules: one tool per role, and at most three tools with a similar function in the light profile. The full profile adds specialised tools for advanced scenarios.

### Phase 1: passive reconnaissance (OSINT)

| Tool | Profile | Role |
|---|---|---|
| `whois` | light | Information about a domain or IP |
| `theHarvester` | light | Harvests emails, subdomains and IPs from public sources |
| `dnsrecon` | light | Full DNS enumeration (zone transfers, brute force, reverse lookups) |
| `amass` | full | Active and passive subdomain enumeration (broad source coverage) |
| `subfinder` | full | Fast passive subdomain discovery |

### Phase 2: scanning and enumeration

| Tool | Profile | Role |
|---|---|---|
| `nmap` | light | Reference scanner: ports, services, OS, NSE scripts. Also provides `ncat` and `nping` |
| `masscan` | light | Very fast port scanning over large ranges (complements nmap: speed vs. depth) |
| `enum4linux-ng` | light | SMB, NetBIOS and LDAP enumeration |
| `smbclient` | light | Interaction with SMB shares (provided by the `samba` package) |
| `snmp-check` | light | Structured SNMP enumeration |
| `snmpwalk`, `snmpget` | light | Raw SNMP queries (`net-snmp` package, a different role from snmp-check) |
| `rustscan` | full | Ultra-fast port scanner, hands off to nmap for detail |

### Phase 3: web analysis

| Tool | Profile | Role |
|---|---|---|
| `gobuster` | light | Directory, vhost and DNS brute forcing |
| `ffuf` | light | Advanced HTTP fuzzing: parameters, headers, POST bodies |
| `nikto` | light | Detection of misconfigurations and outdated versions |
| `burpsuite` | light | Intercepting proxy (GUI, x86_64 only, requires `allowUnfree`) |
| `sqlmap` | light | Automated SQL injection |
| `whatweb` | light | Web technology fingerprinting |
| `firefox` | light | Browser with uBlock Origin pre-installed (enterprise policies) |
| `feroxbuster` | full | Recursive directory brute forcing (Rust, fast) |
| `nuclei` | full | Template-based vulnerability scanner (YAML templates) |
| `wpscan` | full | Dedicated WordPress scanner (themes, plugins, users) |
| `zap` | full | OWASP ZAP intercepting proxy (open source alternative to Burp) |

### Phase 4: exploitation

| Tool | Profile | Role |
|---|---|---|
| `msfconsole` (Metasploit) | light | Exploitation framework |
| `searchsploit` (exploitdb) | light | Offline search in the Exploit-DB database |
| `nxc` (netexec) | light | Multi-protocol network exploitation (SMB, WinRM, LDAP, SSH…), successor to CrackMapExec |

### Phase 5: password attacks

| Tool | Profile | Role |
|---|---|---|
| `john` | light | Versatile offline cracking (CPU) |
| `hashcat` | light | Offline cracking with advanced attack modes and GPU support |
| `hydra` | light | Online brute forcing of network services |
| `hashid` | light | Identifies the type of a hash |
| `crunch` | full | Custom wordlist generator (patterns, charsets) |
| `hcxtools` | full | Wi-Fi handshake capture and conversion (WPA/WPA2) |

### Phase 6: post-exploitation and privesc

| Tool | Profile | Role |
|---|---|---|
| `pspy` | light | Process monitoring without root privileges |
| `chisel` | light | TCP/UDP tunnelling and pivoting over HTTP |
| `linpeas.sh` | light | Linux privilege escalation enumeration (downloaded by `fetch-wordlists`) |

### Phase 7: network and sniffing

| Tool | Profile | Role |
|---|---|---|
| `wireshark` | light | Packet capture and analysis (GUI) |
| `tcpdump` | light | Command-line capture, scriptable, no interface needed |
| `nc` (netcat-gnu) | light | Network Swiss army knife (listening, connections, transfers) |
| `socat` | light | Bidirectional relays, TLS, advanced redirections |
| `ettercap` | full | MITM attacks on LAN (ARP spoofing, sniffing) |
| `ngrep` | full | Real-time network grep (pattern matching on traffic) |
| `proxychains-ng` | full | Force any program's traffic through proxies (SOCKS/HTTP) |

### Phase 8: reverse engineering and pwn

| Tool | Profile | Role |
|---|---|---|
| `ghidra` | light | Decompilation and static analysis (GUI) |
| `r2` (radare2) | light | Command-line binary analysis, scriptable |
| `gdb` | light | Debugger |
| `pwndbg` | light | gdb extension for dynamic analysis (official `pwndbg/pwndbg` flake) |
| `python3` + `pwntools` | light | Scripting binary exploits |
| `rizin` | full | radare2 fork with modernised API (alternative/complement) |
| `jadx` | full | Java/Android decompiler (APK → readable source) |
| `yara` | full | Pattern matching engine for malware detection and triage |
| `python3` + `impacket` | full | Python classes for Windows network protocols (SMB, LDAP, Kerberos) |
| `python3` + `scapy` | full | Network packet crafting and manipulation |

### Phase 9: forensics and steganography

| Tool | Profile | Role |
|---|---|---|
| `binwalk` | light | Analysis and extraction of firmware and nested files |
| `steghide` | light | Steganography |
| `exiftool` | light | Reading and writing metadata |
| `foremost` | light | File carving from disk images |
| `sleuthkit` | full | Filesystem analysis (disk images, partitions) |
| `testdisk` | full | Partition and deleted file recovery |

### Phase 10: cross-cutting utilities

| Tool | Profile | Role |
|---|---|---|
| `curl`, `wget` | light | HTTP requests |
| `jq` | light | JSON parsing |
| `python3` | light | General scripting with `requests`, `beautifulsoup4`, `pycryptodome`, `pwntools` |
| `arsenal` | light | Pentest command cheatsheet (Orange Cyberdefense) |
| `openvpn` | light | VPN connections (HTB, THM) |
| `tmux` | light | Terminal multiplexer |
| `file`, `strings`, `xxd` | light | Basic file analysis (`strings` comes from binutils) |
| `git` | light | Repository root detection |
| `rlwrap` | full | Readline wrapper for programs without history (nc, etc.) |
| `p7zip` | full | 7z compression/decompression and various formats |
| `unzip` | full | ZIP archive extraction |
| `dos2unix` | full | Line ending conversion (useful for transferred files) |

## 10. Commands and aliases inside the container

| Command | Effect |
|---|---|
| `serve <port>` | Python HTTP server on the given port (default 8000) |
| `listen <port>` | Netcat listening on the given port |
| `fetch-wordlists <minimal\|full>` | Downloads wordlists and linpeas into `/workspace/wordlists` |

The prompt shows `[NYX:LIGHT]` or `[NYX:FULL]` in purple, or `[NYX:VPN:LIGHT]` / `[NYX:VPN:FULL]` when a VPN is active.

Tmux is pre-configured inside the container with mouse support, 50000-line history, and windows numbered from 1.

## 11. Alternative: devShell mode (no container)

If you prefer to use the tools directly on your host without a container, you can use the traditional `nix develop` mode:

```bash
cd pentest-env
nix develop .#light  # light profile (~7 GiB, all tools on host)
nix develop .#full   # full profile (~20-30 GiB, extended arsenal)
```

With direnv:

```bash
direnv allow
```

This mode does not require Docker or Podman. Tools run directly on the host through the Nix store. The first `nix develop` downloads and builds the environment (several minutes); subsequent runs are instant.

The `ctf-vpn` script is available in devShell mode for isolated VPN via network namespaces (Linux only, requires `sudo`).

## 12. Environment variables

| Variable | Default | Effect |
|---|---|---|
| `NYX_RUNTIME` | auto-detected | Force `docker` or `podman` |
| `NYX_FLAKE` | local flake or `github:PurpleFlood/pentest-env/nix-container` | Flake source for `nyx install` |

## 13. Adding a tool to the flake

1. Check that the package exists: `nix search nixpkgs#<name>`.
2. Add the name to the list of the relevant phase in `nix/tools.nix`:
   - In the base `groups` section if it belongs in the light profile.
   - In the `extraGroups` section if it belongs only in the full profile.
   - Add a comment if the choice is not obvious.
3. If the package is not in nixpkgs: write an expression in `nix/` (template: `nix/arsenal.nix`), or install it with pip into a venv.
4. Verify with `nix flake check --no-build`, then rebuild the image with `nyx install`.
5. Update `flake.lock` only when needed: `nix flake update <input>`.

After a change, run `git add` before building: nix only takes into account files tracked by git.

## 14. Repository structure

```
flake.nix               # main flake: devShells, packages, Docker images
flake.lock              # pinned versions
nix/
  tools.nix             # tools by phase, profile-aware (light/full)
  docker.nix            # Docker image builder (dockerTools.buildLayeredImage)
  nyx.nix               # nyx CLI packaging
  arsenal.nix           # arsenal (available in nixpkgs)
  netns.nix             # ctf-vpn packaging (devShell mode)
  shell-hook.nix        # scripts, rc file, banner (devShell mode)
scripts/
  nyx.sh                # nyx CLI source
  nyx-entrypoint.sh     # container entrypoint
  ctf-init.sh           # CTF workspace creation (devShell mode)
  ctf-vpn.sh            # isolated VPN in a namespace (devShell mode)
  fetch-wordlists.sh    # wordlists and linpeas
wordlists/              # gitignored, filled by fetch-wordlists
tools/                  # gitignored, linpeas.sh
.envrc                  # direnv: use flake
```

## 15. Technical decisions

| Topic | Choice | Reason |
|---|---|---|
| Containerisation | `dockerTools.buildLayeredImage` | Deterministic OCI images built by Nix, no Dockerfile needed |
| Runtime | Podman (priority) or Docker | Auto-detected; Podman is rootless and OCI-native |
| Profiles | `light` (default) / `full` | Same flake produces both images; `nyx install full` for the extended arsenal |
| CLI | `nyx` (writeShellApplication) | Single command, shellchecked at build time, no external dependencies |
| Workspaces | `~/nyx-workspace/<name>/` | Persistent directories mounted into containers |
| VPN | OpenVPN inside the container | No host network impact, no namespace complexity |
| GUI | X11/Wayland forwarding | Display socket and variables passed to the container |
| Firefox | `wrapFirefox` + enterprise policies | uBlock Origin pre-installed at first launch |
| `pwndbg` | `pwndbg/pwndbg` flake input | Not in nixpkgs |
| Arsenal | Available in nixpkgs | `nix/arsenal.nix` re-exports the package |
| Scripts | `writeShellApplication` | Adds `set -euo pipefail` and runs shellcheck at build time |
| Platform-specific packages | Filtered with `availableOn` | For example, burpsuite only exists on x86_64 |

## 16. Usage tips

- Before starting an HTB machine, create a workspace with `nyx start <name>`, then save the scans in `scans/`.
- Use `masscan` to quickly find open ports, then `nmap -sCV -p <ports>` for details.
- For a web target: `whatweb`, then `gobuster` or `ffuf`, then Burp Suite as a proxy (`127.0.0.1:8080`). For forms, use `sqlmap -r request.txt`.
- For hashes: `hashid <hash>` to identify the type, then `john` or `hashcat -m <mode>`.
- For Linux privesc: run `linpeas.sh`, transferred via `serve` and `curl`.
- For binaries: `checksec` through `pwndbg` in gdb, `r2`, or `ghidra`.
- For pivoting: `chisel server` on the attacker machine and `chisel client` on the target.
- **Full profile extras**: `proxychains-ng` for tunnelling through SOCKS proxies, `nuclei` for automated vuln scanning with templates, `impacket` for Windows protocol attacks (secretsdump, psexec, etc.), `yara` for malware triage.
