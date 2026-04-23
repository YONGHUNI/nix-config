# nix-config

NixOS WSL configuration managed with flakes.

## What's included

- **NixOS on WSL2** with flakes enabled
- **Kerberos (GSSAPI)** authentication for MPCDF HPC systems
- **OpenSSH with Kerberos** support for single sign-on
- **gh** CLI and **git**

## Usage

```bash
# Apply configuration
nrs

# Test without persisting (rollback on reboot)
nrt
```

## Setup on a new machine

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
sudo nixos-rebuild switch --flake ~/nix-config#nixos
```
