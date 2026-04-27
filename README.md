# nix-config

NixOS WSL configuration managed with flakes. This repository owns the WSL system layer: Nix settings, base command-line tools, SSH/Kerberos configuration, and small rebuild aliases.

Project-specific data science environments should live in each project directory, usually through a project `flake.nix`, `devShell`, or another local environment manager.

## What's included

- NixOS on WSL2 with flakes enabled
- Automatic Nix store optimization and garbage collection for generations older than 7 days
- OpenSSH with Kerberos/GSSAPI support for MPCDF access
- Kerberos realm configuration for `IPP-GARCHING.MPG.DE`
- Base shell/development tools: `vim`, `tmux`, `git`, `gh`, `htop`, `tree`, `jq`, `wget`, `unzip`
- Base language/editor tools: `python3`, `pyright`, `black`, `yaml-language-server`, `nil`, `statix`, `nixpkgs-fmt`
- Bash aliases: `nrs` for rebuild switch, `nrt` for rebuild test

## Common Commands

```bash
# Apply the current configuration
nrs

# Test the configuration without making it the boot default
nrt

# Update flake inputs and apply the new system generation
sudo nix flake update && sudo nixos-rebuild switch --flake ~/nix-config#nixos
```

The flake output name is `nixos`, so `~/nix-config#nixos` means `nixosConfigurations.nixos` in `flake.nix`.

## SSH Workflow

```bash
kinit yhsuh@IPP-GARCHING.MPG.DE
ssh gate
ssh raven
```

The first command obtains the Kerberos ticket. The gateway login may still require OTP, while subsequent SSH hops can use delegated credentials when configured by the remote side.

## Setup on a New WSL NixOS Machine

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
sudo nixos-rebuild switch --flake ~/nix-config#nixos
```

After rebuilding, install the shared user-level configuration from the dotfiles repository.

## Scope

Keep this repository focused on system-wide WSL basics. Put heavy or project-specific packages such as NumPy, pandas, Jupyter, CUDA, and ML libraries in project-local environments.

## Related

- [dotfiles](https://github.com/YONGHUNI/dotfiles) - shared shell, Vim, tmux, and R configuration for WSL and Raven
