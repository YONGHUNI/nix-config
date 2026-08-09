# Research VM (`nixos-research`)

## Purpose

`nixos-research` is the primary NixOS guest for GPU-accelerated research workloads on the Proxmox homelab.

The VM provides a stable operating-system layer with NVIDIA support, remote SSH access, and persistent research storage. Project-specific runtimes remain outside the system configuration so that individual research projects can pin their own dependencies independently.

## Configuration entry point

The host is exposed by `flake.nix` as:

```text
nixosConfigurations.nixos-research
```

and is implemented in:

```text
hosts/nixos-research/
├── configuration.nix
└── hardware-configuration.nix
```

Build or apply it with:

```bash
cd ~/nix-config
sudo nixos-rebuild build --flake .#nixos-research
sudo nixos-rebuild switch --flake .#nixos-research
```

## Current guest configuration

The current configuration provides:

- NixOS 26.05
- UEFI boot with systemd-boot
- hostname `nixos-research`
- NetworkManager
- OpenSSH
- root SSH login disabled
- SSH password authentication disabled
- authorized-key access for user `yonghun`
- NVIDIA graphics support
- Nouveau kernel module blacklisted
- NVIDIA open kernel modules enabled
- NVIDIA modesetting enabled
- QEMU guest agent integration
- persistent `/data` filesystem
- a minimal set of administrative packages

The system intentionally avoids installing project-specific research stacks globally.

## Virtual hardware assumptions

This configuration assumes that Proxmox already supplies the required virtual hardware.

The VM-side configuration does not create or manage:

- VM CPU topology
- VM memory allocation
- Proxmox virtual disks
- PCIe passthrough
- IOMMU/VFIO configuration
- Proxmox bridges
- ZFS pools

Those are hypervisor responsibilities documented at a higher level in [Homelab architecture](homelab.md).

`hardware-configuration.nix` was generated for the current VM and contains machine-specific filesystem UUIDs. Review or regenerate it if the VM disk layout changes substantially.

## GPU

The NVIDIA GPU is passed through by Proxmox and configured from inside the guest by NixOS.

The guest currently declares:

```nix
boot.blacklistedKernelModules = [ "nouveau" ];
hardware.graphics.enable = true;
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia = {
  open = true;
  modesetting.enable = true;
};
```

A useful troubleshooting boundary is:

```text
GPU absent from `lspci`
    → investigate Proxmox passthrough / IOMMU / VFIO

GPU visible in `lspci`, NVIDIA driver failing
    → investigate NixOS guest driver configuration
```

After rebuilding, the primary guest-side sanity check is:

```bash
nvidia-smi
```

## Remote access

OpenSSH is enabled with a key-only policy:

```text
PermitRootLogin = no
PasswordAuthentication = false
```

The normal administrative user is:

```text
yonghun
```

Its authorized SSH key is declared in the NixOS configuration, making key authorization reproducible with the host configuration.

VPN routing, router configuration, Wake-on-LAN, and access to the Proxmox management interface are deliberately outside the guest configuration.

## Persistent research storage

A dedicated filesystem is mounted at:

```text
/data
```

The current configuration identifies this filesystem by UUID and mounts it as ext4 with discard enabled.

The following directories are created declaratively with `systemd-tmpfiles`:

```text
/data/yonghun/
├── projects/
├── datasets/
└── scratch/
```

### `projects`

Use for research repositories and working directories.

A typical project can contain its own reproducible environment:

```text
/data/yonghun/projects/example-project/
├── flake.nix
├── flake.lock
├── src/
└── ...
```

### `datasets`

Use for datasets that should survive project-environment rebuilds and may be shared by multiple projects.

Large datasets should not be committed to `nix-config`.

### `scratch`

Use for temporary, reproducible, or disposable intermediate products.

Anything stored here should be treated as data that can be regenerated when practical.

## Project environments

The research VM should remain a relatively thin host.

Do not add Python, R, PyTorch, CUDA user-space toolkits, GDAL stacks, or other research dependencies globally merely because one project needs them.

Prefer project-local environments such as:

```bash
cd /data/yonghun/projects/example-project
nix develop
```

This keeps responsibilities separated:

```text
nix-config
  operating system + driver + SSH + persistent mounts

project flake
  Python/R + geospatial stack + ML libraries + project tools
```

System-level NVIDIA driver support remains in `nix-config`; application-level CUDA dependencies can be pinned per project where appropriate.

## Administrative tools

The system configuration currently installs only a small administrative base:

```text
git
vim
tmux
curl
```

Additional general-purpose host administration tools may be added here when they are genuinely useful across projects. Research-specific software should stay project-local.

## Rebuild workflow

Before switching a changed configuration, build it first:

```bash
cd ~/nix-config
git pull
nix flake check
sudo nixos-rebuild build --flake .#nixos-research
```

If the build succeeds:

```bash
sudo nixos-rebuild switch --flake .#nixos-research
```

For changes involving GPU drivers, boot configuration, filesystems, or networking, verify the relevant functionality before ending the maintenance session.

Useful checks include:

```bash
systemctl status qemu-guest-agent
systemctl status sshd
findmnt /data
nvidia-smi
```

## Recreating the VM

Cloning this repository is not sufficient to recreate the entire Proxmox guest from nothing. The hypervisor must first provide equivalent virtual hardware and storage.

After creating the VM and restoring the expected disk layout:

1. generate or review `hardware-configuration.nix`
2. ensure the persistent data disk has the expected filesystem or update its UUID
3. ensure the passed-through GPU is visible to the guest
4. clone `nix-config`
5. build `.#nixos-research`
6. switch to the configuration
7. verify SSH, `/data`, QEMU guest integration, and NVIDIA operation

## Related documentation

- [Homelab architecture](homelab.md)
- [Repository overview](../README.md)
