# nix-config

Cross-platform Nix configuration for NixOS WSL and macOS, managed with flakes.

## Structure

```
nix-config/
├── flake.nix              # Entry point (nixos + darwin)
├── modules/
│   └── common.nix         # Shared: git, gh, Kerberos
└── hosts/
    ├── wsl/default.nix    # NixOS WSL specific
    └── mac/default.nix    # macOS (nix-darwin) specific
```

## What's included

**Shared (all platforms):**
- Flakes enabled
- Kerberos (GSSAPI) for MPCDF HPC systems (realm: `IPP-GARCHING.MPG.DE`)
- git, gh CLI

**WSL:**
- OpenSSH with Kerberos support
- Shell aliases: `nrs` (rebuild switch), `nrt` (rebuild test)

**macOS:**
- nix-darwin system defaults (dock autohide, Finder extensions)
- Touch ID for sudo
- Shell alias: `nrs` (darwin-rebuild switch)

## Usage

### NixOS WSL

```bash
# Apply configuration
nrs

# Test without persisting (rollback on reboot)
nrt

# Daily SSH workflow
kinit yhsuh@IPP-GARCHING.MPG.DE   # password once
ssh gate                            # OTP once
ssh raven                           # auto (ticket delegation)
```

### macOS (first time)

```bash
# Install nix
curl -L https://nixos.org/nix/install | sh

# Install nix-darwin
nix run nix-darwin -- switch --flake ~/nix-config#mac

# Subsequent rebuilds
nrs
```

## Setup on a new machine

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config

# NixOS WSL
sudo nixos-rebuild switch --flake ~/nix-config#nixos

# macOS
nix run nix-darwin -- switch --flake ~/nix-config#mac
```

## Related

- [dotfiles](https://github.com/YONGHUNI/dotfiles) — shell, vim, tmux configuration
