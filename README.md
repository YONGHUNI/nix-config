# nix-config

Personal NixOS configurations managed with flakes.

This repository currently manages two environments:

- **LG Gram (`gram`)**: NixOS desktop
- **WSL (`wsl`)**: NixOS-WSL development environment

System configuration, hardware support, desktop applications, and general-purpose command-line tools belong in this repository.

Project-specific runtimes and dependencies—such as Python or R versions, geospatial libraries, machine-learning frameworks, and project-specific CUDA toolkits—should be managed within each project's reproducible environment, preferably through a Nix flake and `devShell`.

System-level hardware configuration, including GPU drivers, remains in this repository.

## Repository layout

```text
.
├── flake.nix
├── flake.lock
├── README.md
├── docs/
│   ├── gram-touchpad.md
│   ├── hop.md
│   └── kakaotalk-bottles.md
├── home/
│   └── yonghun.nix
├── hosts/
│   ├── gram/
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── home.nix
│   └── wsl/
│       └── configuration.nix
├── modules/
│   └── nixos/
│       └── laptop.nix
└── pkgs/
    └── hop/
        └── default.nix
```

## Configuration overview

### LG Gram

- NixOS 26.05
- KDE Plasma 6 desktop
- Home Manager
- Plasma Manager
- Fcitx5 Korean input
- systemd-boot
- LUKS-encrypted root and swap
- TPM2-based LUKS unlocking
- GeoClue-based automatic time-zone selection
- Flatpak and Bottles
- System Wine for the KakaoTalk Bottle
- HOP HWP/HWPX editor
- LG Gram touchpad hotkey and LED handling
- Base desktop and command-line tools

### WSL

- NixOS-WSL
- NixOS 25.11 package set retained
- OpenSSH with Kerberos/GSSAPI support
- Kerberos realm configuration for MPCDF
- Automatic Nix store optimization
- Automatic cleanup of generations older than seven days
- Base command-line and development tools
- Python, YAML, and Nix language tooling
- `nrs` and `nrt` rebuild aliases

## Common commands

### Gram

```bash
cd ~/nix-config

# Evaluate the flake
nix flake check

# Build without changing the active system generation
sudo nixos-rebuild build --flake .#gram

# Apply the configuration
sudo nixos-rebuild switch --flake .#gram
```

### WSL

```bash
cd ~/nix-config

sudo nixos-rebuild build --flake .#wsl
sudo nixos-rebuild switch --flake .#wsl
```

The WSL configuration also provides the following aliases:

```bash
nrt
nrs
```

- `nrt`: test the `wsl` configuration
- `nrs`: switch to the `wsl` configuration

## Updating flake inputs

The Gram and WSL configurations use separate nixpkgs inputs:

- `nixpkgs`: NixOS 26.05 for the Gram
- `nixpkgs-wsl`: NixOS 25.11 for WSL

Update all flake inputs with:

```bash
cd ~/nix-config
nix flake update
```

Review the lock-file changes before rebuilding:

```bash
git diff flake.lock
```

Then build and apply the relevant configuration:

```bash
sudo nixos-rebuild build --flake .#gram
sudo nixos-rebuild switch --flake .#gram
```

or:

```bash
sudo nixos-rebuild build --flake .#wsl
sudo nixos-rebuild switch --flake .#wsl
```

## Deploying

### Gram

Clone the repository:

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
cd ~/nix-config
```

The `gram` configuration is tied to the current LG Gram hardware and disk layout.

In particular, it contains machine-specific configuration for:

- EFI and filesystem UUIDs
- LUKS root and swap devices
- Btrfs subvolumes
- TPM2-based unlocking
- LG-specific input and LED behavior

`hosts/gram/hardware-configuration.nix` must not be reused unchanged on another machine.

TPM enrollment is machine-local state and is not reproduced by cloning this repository. Each encrypted volume must be enrolled separately with `systemd-cryptenroll` when rebuilding the machine from scratch.

After restoring the expected disk and encryption layout:

```bash
sudo nixos-rebuild switch --flake .#gram
```

### WSL

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
cd ~/nix-config
sudo nixos-rebuild switch --flake .#wsl
```

## Home Manager

Shared user packages and user-level configuration are managed in:

```text
home/yonghun.nix
```

This includes:

- shared dotfiles
- user-level command-line tools
- the Fcitx5 input-method profile
- the locally packaged HOP application

LG Gram-specific Plasma configuration is managed in:

```text
hosts/gram/home.nix
```

This includes:

- the remapped touchpad hotkey
- automatic touchpad discovery through KWin
- touchpad LED synchronization

## Documentation

- [LG Gram 터치패드 Fn+F5 및 상태 LED](docs/gram-touchpad.md)
- [HOP 패키징 및 실행](docs/hop.md)
- [Bottles와 카카오톡](docs/kakaotalk-bottles.md)

## Repository scope

Included:

- NixOS host configurations
- Home Manager user configuration
- Hardware and boot settings
- General-purpose system and user tools
- Locally packaged desktop applications
- Reproducible Flatpak declarations
- Host-level Wine and application support

Excluded:

- Project-specific Python and R environments
- Project-specific CUDA toolkits and machine-learning frameworks
- Large datasets
- Private keys and credentials
- Bottles and Wine prefix data
- Application-generated files
- Nix build-result symlinks such as `result`

## Related repositories

- [dotfiles](https://github.com/YONGHUNI/dotfiles): shared Bash, Vim, tmux, and R configuration
