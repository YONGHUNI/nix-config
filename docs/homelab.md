# Homelab architecture

## Purpose

The homelab provides a remotely accessible research-computing platform while keeping NixOS guest configuration reproducible in this repository.

The infrastructure is split into layers. Proxmox manages the physical machine, virtualization, storage, and device assignment. This repository manages the guest-side NixOS systems and services running on top of that infrastructure.

## Architecture

```text
Physical server
└── Proxmox VE
    ├── virtual networking
    ├── VM/LXC storage
    ├── PCIe / GPU passthrough
    ├── NixOS research VM (`nixos-research`)
    │   ├── NVIDIA GPU driver
    │   ├── SSH access
    │   ├── persistent `/data` mount
    │   └── research workspace
    └── NixOS DNS LXC (`nixos-dns`)
        ├── AdGuard Home
        │   ├── upstream DNS
        │   └── local `home.arpa` rewrites
        └── Caddy
            ├── `dns.home.arpa`
            └── `proxmox.home.arpa`
```

The managed homelab guests are exposed by two flake outputs:

```text
flake.nix
└── nixosConfigurations
    ├── nixos-research
    │   └── hosts/nixos-research/configuration.nix
    └── nixos-dns
        └── hosts/nixos-dns/configuration.nix
```

## Responsibility boundary

### Proxmox layer

The Proxmox host is responsible for infrastructure that must exist before NixOS boots:

- physical hardware management
- VM and LXC creation and lifecycle
- CPU and memory allocation
- virtual disks
- VM/LXC storage and ZFS configuration
- virtual bridges and network attachment
- PCIe device assignment and GPU passthrough
- boot ordering and recovery at the hypervisor level

These settings are not currently declared by `nix-config`.

### NixOS guest layer

The `nixos-research` configuration manages:

- hostname and NetworkManager
- systemd-boot inside the VM
- OpenSSH and SSH key authorization
- disabled root and password SSH login
- NVIDIA guest driver configuration
- persistent research storage at `/data`
- QEMU guest integration
- administrative command-line tools
- research directory hierarchy

The `nixos-dns` configuration manages:

- OpenSSH and SSH key authorization
- [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)
- local [`home.arpa`](https://www.rfc-editor.org/rfc/rfc8375.html) DNS rewrites
- [Caddy](https://caddyserver.com/) reverse proxying
- local HTTPS through Caddy's internal CA
- guest firewall rules for DNS and HTTPS

### Project layer

Research projects keep their computational dependencies outside the host configuration.

Examples include:

- Python and R versions
- geospatial libraries
- machine-learning frameworks
- project-specific CUDA user-space dependencies
- notebooks and analysis tools

Prefer a project-local Nix flake and `devShell` where practical. This keeps the research VM small and stable while allowing each project to pin its own environment.

## Storage model

### Hypervisor storage

Proxmox owns the storage used for VM/LXC disks and snapshots. The homelab includes ZFS-backed storage on the Proxmox side.

The exact pool layout, ARC tuning, disk replacement procedure, and snapshot policy belong to the Proxmox infrastructure rather than this repository unless they are later managed declaratively elsewhere.

### Guest research storage

Inside `nixos-research`, a separate persistent filesystem is mounted at:

```text
/data
```

The NixOS configuration creates:

```text
/data/yonghun/
├── projects/
├── datasets/
└── scratch/
```

- `projects/`: research repositories and working code
- `datasets/`: persistent datasets shared across projects
- `scratch/`: disposable or reproducible intermediate data

This keeps research data separate from the VM system disk.

## GPU model

The physical NVIDIA research GPU is assigned to the VM by Proxmox. The hypervisor-side passthrough setup is outside this repository.

Once the GPU is visible inside the guest, `hosts/nixos-research/configuration.nix` configures the NixOS NVIDIA driver stack.

When troubleshooting:

1. If the PCI device is not visible in the VM, check Proxmox/IOMMU/VFIO first.
2. If the device is visible but the NVIDIA driver does not work, check the NixOS guest configuration.

## Networking and remote access

The managed guests attach to the homelab network through Proxmox virtual networking rather than an additional guest NAT layer.

Remote-access transport, router configuration, VPN access, Wake-on-LAN, and Proxmox host management remain infrastructure concerns outside this repository.

SSH on the NixOS guests is configured conservatively:

- root login disabled
- password authentication disabled
- public-key authentication used for the main user

## Local DNS

The DNS container is `192.168.0.202`. AdGuard Home listens on port 53 and provides both upstream resolution and local rewrites.

| Name | Address | Purpose |
| --- | --- | --- |
| `router.home.arpa` | `192.168.0.1` | Router |
| `pve.home.arpa` | `192.168.0.200` | Proxmox host |
| `gpu.home.arpa` | `192.168.0.201` | Research VM |
| `dns.home.arpa` | `192.168.0.202` | AdGuard Home through Caddy |
| `proxmox.home.arpa` | `192.168.0.202` | Proxmox web UI through Caddy |

`home.arpa` is the IETF-designated special-use domain for residential networks; see [RFC 8375](https://www.rfc-editor.org/rfc/rfc8375.html).

## HTTPS reverse proxy

Caddy fronts the homelab web interfaces so they can be reached without explicit service ports:

```text
https://dns.home.arpa
    → Caddy
    → http://127.0.0.1:3000

https://proxmox.home.arpa
    → Caddy
    → https://192.168.0.200:8006
```

See the Caddy documentation for [`reverse_proxy`](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) and [`tls internal`](https://caddyserver.com/docs/caddyfile/directives/tls).

The Proxmox upstream currently uses `tls_insecure_skip_verify`. This keeps the proxy working with the Proxmox certificate but disables certificate verification between Caddy and the upstream. It should eventually be replaced with explicit trust of the Proxmox certificate or CA.

AdGuard Home's direct web port also remains available in addition to the Caddy endpoint.

## Local TLS

The `home.arpa` HTTPS endpoints use Caddy's internal CA rather than a public ACME certificate.

The public root certificate is stored at:

```text
certs/caddy-root.crt
```

The Gram configuration trusts it declaratively:

```nix
security.pki.certificateFiles = [
  ../../certs/caddy-root.crt
];
```

Other clients must trust the same root certificate in their OS or browser trust store. The root certificate is public material and may be distributed to clients. The corresponding CA private key must never be committed or distributed.

## Operational principle

Keep each layer responsible only for what it can reproduce reliably:

```text
Proxmox
  physical resources / virtualization / ZFS / passthrough / VM networking

nix-config
  NixOS guests / drivers / SSH / mounts / DNS / reverse proxy / local CA trust

project repository
  research runtime / libraries / analysis dependencies
```

This reduces coupling between long-lived homelab infrastructure and short-lived research environments.

## Related documentation

- [Research VM (`nixos-research`)](research-vm.md)
- [Repository overview](../README.md)
