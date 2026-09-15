# UGA OpenConnect VPN

## Purpose

The LG Gram uses NetworkManager and KDE Plasma to connect to the University of Georgia VPN at:

```text
remote.uga.edu
```

The preferred path is the normal KDE network tray:

```text
KDE Plasma
    ↓
Plasma-NM
    ↓
NetworkManager-openconnect
    ↓
OpenConnect
    ↓
UGA Cisco VPN
```

The VPN connection profile is declared through NixOS rather than being created manually in NetworkManager.

No usernames, passwords, Duo credentials, VPN cookies, or other authentication secrets are stored in this repository.

## Why local patches are required

UGA's Cisco VPN exposes several authentication paths whose behavior depends on the OpenConnect client configuration.

Two details were required for reliable non-browser authentication from Plasma.

### Cisco-compatible User-Agent

Plasma-NM normally identifies itself using a User-Agent similar to:

```text
OpenConnect VPN Agent (PlasmaNM - running on KDE) v9.12-unknown
```

During testing, UGA's VPN gateway responded to the initial XML authentication POST from this client with:

```text
HTTP/1.1 404 Not Found
```

OpenConnect then fell back to the legacy `+webvpn+` authentication path.

The legacy form contained primary and secondary authentication fields and was not the intended authentication flow.

Using OpenConnect's AnyConnect-compatible User-Agent instead:

```text
AnyConnect-compatible OpenConnect VPN Agent v9.12-unknown
```

caused the same XML authentication request to receive:

```text
HTTP/1.1 200 OK
XML POST enabled
```

The declarative NetworkManager profile therefore sets this User-Agent explicitly.

### `no-external-auth`

The desired flow also requires OpenConnect's `no_external_auth` behavior.

With external authentication disabled, OpenConnect omits external SSO capabilities from the initial authentication request and allows the gateway to return the normal username/password XML authentication form.

The OpenConnect version currently used by this configuration contains the internal behavior but does not expose all of the API plumbing required by NetworkManager and Plasma-NM. The repository therefore carries three local patches:

```text
patches/
├── openconnect-no-external-auth.patch
├── networkmanager-openconnect-no-external-auth.patch
└── plasma-nm-openconnect-no-external-auth.patch
```

They provide the path:

```text
NetworkManager profile
    ↓
no-external-auth=yes
    ↓
Plasma-NM / NetworkManager-openconnect
    ↓
openconnect_set_no_external_auth()
    ↓
OpenConnect
```

`hosts/gram/configuration.nix` applies the patched packages through a nixpkgs overlay.

## Declarative VPN profile

The `UGA VPN` NetworkManager profile is managed by:

```nix
networking.networkmanager.ensureProfiles.profiles."UGA VPN"
```

Important values include:

```nix
gateway = "remote.uga.edu";
protocol = "anyconnect";

no-external-auth = "yes";
useragent = "AnyConnect-compatible OpenConnect VPN Agent v9.12-unknown";
```

The profile is intentionally not configured to autoconnect.

Authentication secrets are not part of the Nix configuration and are requested interactively when connecting.

Because the profile is declarative, NetworkManager materializes it at runtime under:

```text
/var/run/NetworkManager/system-connections/
```

A manually created KDE/NetworkManager profile with the same name should not be kept alongside the declarative profile.

## Normal use

Open the KDE network tray and connect to:

```text
UGA VPN
```

Select the normal UGA group when requested and complete username/password and Duo authentication.

A successful connection creates a tunnel interface such as:

```text
tun0
```

NetworkManager can be used to verify that the VPN is active:

```bash
nmcli -t -f NAME,TYPE,DEVICE connection show --active
```

The output should contain an active `UGA VPN` connection.

## Command-line fallback

If the KDE/NetworkManager integration is temporarily broken, OpenConnect can be used directly:

```bash
sudo openconnect \
  --protocol=anyconnect \
  --authgroup='01 Default' \
  --no-external-auth \
  remote.uga.edu
```

The stock OpenConnect command-line client already uses the AnyConnect-compatible User-Agent expected by the UGA gateway.

This is the first fallback because it uses the same non-browser authentication flow as the preferred KDE configuration while avoiding Plasma-NM.

## SAML fallback

A second fallback is packaged locally in:

```text
pkgs/openconnect-saml/
```

Run it with:

```bash
openconnect-saml \
  --server remote.uga.edu \
  --authgroup '01 Default' \
  --browser qt
```

This opens a Qt WebEngine authentication window and follows UGA's SAML/Duo authentication flow before passing the resulting authentication state to OpenConnect.

Testing confirmed that the SAML flow reached Duo successfully and subsequently established both CSTP and DTLS VPN connections.

### SAML fallback warnings

During testing, Qt WebEngine reported that `libfido2` was unavailable. This is relevant to USB FIDO2/WebAuthn security keys but did not prevent the tested username/password plus Duo Push flow from completing.

OpenConnect also printed:

```text
Server certificate verify failed: signer not found
```

before continuing to establish the VPN tunnel.

The fallback therefore works functionally, but the certificate warning should be understood and resolved before treating this path as equivalent to a clean certificate-verification result.

## Troubleshooting

### Initial XML POST returns 404

If the log contains:

```text
POST https://remote.uga.edu/
HTTP/1.1 404 Not Found
```

followed by requests to:

```text
/+webvpn+/index.html
```

check the configured User-Agent first.

The expected value for the current configuration is:

```text
AnyConnect-compatible OpenConnect VPN Agent v9.12-unknown
```

### Legacy form shows two password fields

This indicates that OpenConnect has fallen back to the legacy WebVPN form.

Check both:

```text
useragent
no-external-auth
```

in the NetworkManager profile.

### Embedded SSO appears instead of the non-browser form

Verify that the patched Plasma-NM build is active and that `no-external-auth=yes` is present in the VPN profile.

### Duplicate UGA VPN entries

A GUI-created NetworkManager profile may coexist with the declarative `ensureProfiles` entry.

Remove the obsolete manually created profile and keep the declarative one.

## Maintenance

The patches in this repository should be treated as compatibility patches, not permanent forks.

After significant updates to OpenConnect, NetworkManager-openconnect, or Plasma-NM:

1. Check whether upstream now exposes and propagates the required `no-external-auth` functionality.
2. Verify that all three local patches still apply cleanly.
3. Verify that the active Plasma-NM plugin references `openconnect_set_no_external_auth`.
4. Test the KDE connection from an external network.
5. Confirm that the initial XML POST receives HTTP 200 rather than falling back to `+webvpn+`.
6. Revisit the explicitly configured User-Agent.

The current User-Agent contains:

```text
v9.12-unknown
```

and is intentionally pinned to the value that was verified against the UGA VPN gateway. It should be reconsidered when the OpenConnect version changes.

The local patches can be removed once the required functionality is available through the upstream OpenConnect, NetworkManager-openconnect, and Plasma-NM versions used by nixpkgs.
