# nix-config

Personal NixOS configurations managed with flakes.

This repository contains reproducible system configuration for my laptop, research VM, homelab services, and NixOS-WSL environment. Host-level operating system configuration belongs here, while project-specific research environments are kept with their respective projects.

## Systems

| Flake output | Role | Notes |
| --- | --- | --- |
| `gram` | LG Gram laptop | KDE Plasma desktop, Home Manager, hardware-specific laptop configuration, UGA VPN |
| `nixos-research` | GPU research VM | NixOS VM on Proxmox with NVIDIA GPU passthrough and persistent research storage |
| `nixos-dns` | DNS / reverse-proxy LXC | AdGuard Home, local `home.arpa` DNS, Caddy HTTPS reverse proxy |
| `wsl` | NixOS-WSL environment | Generic command-line and development environment |

The Gram, research VM, and DNS container currently use the NixOS 26.05 package set. WSL remains on its separately pinned NixOS 25.11 package set.

## Design

System configuration, hardware support, drivers, desktop integration, and general-purpose tools are managed here.

Project-specific dependencies are intentionally kept outside the system configuration. Python and R versions, geospatial libraries, machine-learning frameworks, and project-specific CUDA user-space dependencies should normally be managed through a project-local Nix dev shell, Pixi environment, or another reproducible project environment.

Shared Bash, Vim, and tmux configuration comes from the [`dotfiles`](https://github.com/YONGHUNI/dotfiles) flake input.

The Proxmox host itself is outside the scope of this repository. This repository manages the NixOS guests running on top of it.

## Repository layout

```text
.
├── hosts/      # per-host NixOS configurations
├── modules/    # reusable NixOS modules
├── home/       # shared Home Manager configuration
├── pkgs/       # locally packaged software
├── patches/    # compatibility and upstream-backport patches
├── docs/       # operational and implementation documentation
├── certs/      # public trust material used by managed systems
├── flake.nix
└── flake.lock
```

## Common commands

Evaluate the flake:

```bash
nix flake check
```

Build a configuration without activating it:

```bash
sudo nixos-rebuild build --flake .#gram
```

Apply a configuration:

```bash
sudo nixos-rebuild switch --flake .#gram
```

Replace `gram` with `nixos-research`, `nixos-dns`, or `wsl` as appropriate.

Update all flake inputs:

```bash
nix flake update
git diff flake.lock
```

When only the shared shell/editor configuration changed:

```bash
nix flake update dotfiles
```

## Documentation

- [Homelab architecture](docs/homelab.md)
- [Research VM (`nixos-research`)](docs/research-vm.md)
- [DNS container (`nixos-dns`)](docs/dns-container.md)
- [UGA OpenConnect VPN](docs/uga-vpn.md)
- [LG Gram touchpad Fn+F5 and status LED](docs/gram-touchpad.md)
- [HOP packaging and execution](docs/hop.md)
- [KakaoTalk with Bottles](docs/kakaotalk-bottles.md)

## Host-specific notes

The `gram` configuration is tied to the current LG Gram hardware and disk layout. Its hardware configuration includes machine-specific filesystem and encryption information and should not be reused unchanged on another machine. TPM enrollment is machine-local state and must be recreated separately when rebuilding the laptop from scratch.

The `nixos-research` configuration assumes that Proxmox already provides the expected virtual hardware, GPU passthrough, boot disk, and persistent data disk.

The `nixos-dns` configuration assumes that the corresponding Proxmox LXC and network attachment already exist.

The WSL configuration is intentionally generic and does not include institution-specific cluster, Kerberos, or SSH configuration.

## Repository scope

Included here are NixOS host configurations, Home Manager configuration, hardware and boot settings, host-level drivers and tools, locally packaged applications, public CA certificates, and guest-side configuration for the managed Proxmox VM and LXC.

Excluded are Proxmox host state, VM/LXC lifecycle management, hypervisor-side ZFS and PCI passthrough configuration, project-specific research environments, datasets, credentials, Wine prefix data, and generated build artifacts.

## Related repositories

- [`dotfiles`](https://github.com/YONGHUNI/dotfiles) — shared Bash, Vim, and tmux configuration
