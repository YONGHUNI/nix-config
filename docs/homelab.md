# Homelab architecture

## Purpose

The homelab provides a remotely accessible research-computing platform while keeping the NixOS guest configuration reproducible in this repository.

The infrastructure is intentionally split into layers. Proxmox manages the physical machine, virtualization, storage, and device assignment. This repository manages the operating system and guest-side configuration of NixOS systems running inside that infrastructure.

## Architecture

```text
Physical server
└── Proxmox VE
    ├── virtual networking
    ├── VM storage
    ├── PCIe / GPU passthrough
    └── NixOS research VM (`nixos-research`)
        ├── NVIDIA GPU driver
        ├── SSH access
        ├── persistent `/data` mount
        └── research workspace
```

The research VM is configured through the `nixos-research` flake output:

```text
flake.nix
└── nixosConfigurations.nixos-research
    └── hosts/nixos-research/configuration.nix
```

## Responsibility boundary

### Proxmox layer

The Proxmox host is responsible for infrastructure that must exist before NixOS boots:

- physical hardware management
- VM creation and lifecycle
- CPU and memory allocation
- virtual disks
- VM storage and ZFS configuration
- virtual bridges and network attachment
- PCIe device assignment and GPU passthrough
- boot ordering and recovery at the hypervisor level

These settings are not currently declared by `nix-config`.

### NixOS guest layer

The `nixos-research` configuration is responsible for guest operating-system state, including:

- hostname and NetworkManager
- systemd-boot inside the VM
- OpenSSH
- SSH key authorization
- disabling SSH password authentication
- NVIDIA guest driver configuration
- mounting the persistent research data filesystem at `/data`
- QEMU guest integration
- administrative command-line tools
- creation of the research directory hierarchy

### Project layer

Research projects should keep their own computational dependencies outside the host configuration.

Examples include:

- Python and R versions
- geospatial libraries
- machine-learning frameworks
- project-specific CUDA user-space dependencies
- notebooks and analysis tools

Prefer a project-local Nix flake and `devShell` where practical. This keeps the research VM itself small and stable while allowing individual projects to pin their own environments.

## Storage model

There are two different storage concerns and they should not be conflated.

### Hypervisor storage

Proxmox owns the storage used for VM disks and snapshots. The current homelab includes ZFS-backed VM storage on the Proxmox side.

The exact pool layout, ARC tuning, disk replacement procedure, and snapshot policy belong to the Proxmox infrastructure rather than this repository unless they are later managed declaratively elsewhere.

### Guest research storage

Inside `nixos-research`, a separate persistent filesystem is mounted at:

```text
/data
```

The NixOS configuration creates the following user-owned hierarchy:

```text
/data/yonghun/
├── projects/
├── datasets/
└── scratch/
```

The intent is:

- `projects/`: research repositories and working code
- `datasets/`: persistent datasets shared across projects
- `scratch/`: disposable or reproducible intermediate data

This separation prevents research data from being coupled unnecessarily to the VM system disk.

## GPU model

The physical NVIDIA research GPU is assigned to the VM by Proxmox. The hypervisor-side passthrough setup is outside this repository.

Once the GPU is visible inside the guest, `hosts/nixos-research/configuration.nix` configures the NixOS NVIDIA driver stack.

This distinction is important when troubleshooting:

1. If the PCI device is not visible in the VM, troubleshoot Proxmox/IOMMU/VFIO first.
2. If the PCI device is visible but the NVIDIA driver does not work, troubleshoot the NixOS guest configuration.

## Networking and remote access

The VM is expected to attach to the homelab network through Proxmox virtual networking rather than being hidden behind an additional guest NAT layer.

Remote-access transport, router configuration, VPN access, Wake-on-LAN, and Proxmox management remain infrastructure concerns outside this repository.

Inside the guest, SSH is intentionally configured conservatively:

- root login disabled
- password authentication disabled
- public-key authentication used for the main user

## Operational principle

The main design rule is to keep each layer responsible only for what it can reproduce reliably:

```text
Proxmox
  physical resources / virtualization / ZFS / passthrough / VM networking

nix-config
  NixOS guest / driver / SSH / mounts / system services

project repository
  research runtime / libraries / analysis dependencies
```

This reduces coupling between the long-lived homelab infrastructure and short-lived research environments.

## Related documentation

- [Research VM (`nixos-research`)](research-vm.md)
- [Repository overview](../README.md)
