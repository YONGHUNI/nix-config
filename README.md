# nix-config

NixOS WSL configuration managed with flakes.

## What's included

- **NixOS on WSL2** with flakes enabled
- **Kerberos (GSSAPI)** authentication for MPCDF HPC systems (realm: `IPP-GARCHING.MPG.DE`)
- **OpenSSH with Kerberos** support for single sign-on
- **git**, **gh** CLI
- Shell aliases: `nrs` (rebuild switch), `nrt` (rebuild test)

## Usage

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

## Setup on a new machine

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
sudo nixos-rebuild switch --flake ~/nix-config#nixos
```

## Related

- [dotfiles](https://github.com/YONGHUNI/dotfiles) — shell, vim, tmux configuration
