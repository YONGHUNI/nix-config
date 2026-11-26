# iPad wireless display (Gram)

KDE Wayland + Krfb + Sunshine + Moonlight. Native 2732x2048, scale 150%.
The tablet tray icon remains available in Plasma; left-click toggles the
display, right-click selects the mode for the next start and shows status,
upstream Wi-Fi, hotspot channel, copy host IP and local Sunshine settings.
If hidden, set iPad Display to Always Shown in Plasma's System Tray settings.

## Modes

- Existing Wi-Fi (explicit fallback): existing streaming behavior, no AP. Select manually; never an automatic fallback.
- Dedicated Hotspot: local AP + DHCP, no default gateway or Internet sharing.
- Hotspot + Internet (default): same AP + DHCP + narrowly scoped IPv4 forwarding/NAT.
  A physical Wi-Fi connection is required in both AP modes.

CLI: `ipad-display start|restart|toggle [wifi|direct|shared]`,
`ipad-display stop|status|info|logs|qr`. The QR command emits PNG to stdout.
Use the tray QR dialog and iPad Camera to join Gram-Display. Moonlight host:
10.42.0.1. The first launch creates a random stable password under
/var/lib/ipad-hotspot (root-only); the runtime QR payload is readable by
wheel members only. Do not share the QR screenshot. DHCP leases 10.42.0.2
to a single client. Sunshine credentials and existing paired clients remain
unchanged.

## First migration

Stop Moonlight, stop the manual hostapd and dnsmasq (Ctrl+C in their
terminals), stop the display, and reboot to clear temporary iptables rules,
interface and forwarding settings from the experiments. Do not run the
manual experiment and managed service concurrently. Build the new NixOS
generation before switching. After activation, restart
`systemctl --user restart ipad-display-tray.service` or log in again.

## Network policy and limitations

The systemd services are on-demand, not enabled at boot; active local wheel
users may start/stop only these three units without an authentication prompt.
NetworkManager does not manage ipad-ap. The service detects the current
STA channel and tries 80/40/20 MHz as appropriate, with 20 MHz on 2.4 GHz.
Regulatory and driver restrictions are respected; no country override.
If the upstream channel changes, a conflicting route appears, a child fails,
or the isolation table disappears, the AP is stopped; manually restart the
display to reselect the channel or choose Existing Wi-Fi. Suspend/logout
also stop the AP. No automatic roaming/reconnect is promised.

A declarative, persistent inet nftables guard defaults to denying AP forwarding and adds restrictive input and forward hooks
alongside the existing NixOS iptables firewall (no global backend change).
A later VPN drop still takes precedence. IPv6 is disabled on the AP only.
Private destinations and all non-physical-Wi-Fi forwarding are dropped.
Local AP input permits only DHCP, the tested Sunshine ports and IPv4 ping.
No VNC or admin port is opened. A default-deny input/output guard restricts the standard Sunshine streaming ports to the dedicated AP/client, except while the explicit Wi-Fi fallback service enables the upstream interface. Mode units conflict; switching modes first stops Sunshine and Krfb. The legacy set is empty in both AP modes, including after failure. The Wi-Fi fallback supervisor clears its permission on exit. The restriction is port-based and assumes Sunshine's default port family. iPadOS still controls its own Wi-Fi auto-join and Moonlight may cache the previous host address. Select Gram-Display and use 10.42.0.1; no automatic LAN fallback is allowed by the host.
No policy routing, VPN DNS, global forwarding, or VPN profiles are changed.
Shared mode enables per-interface forwarding, not global forwarding.
If it enables Wi-Fi forwarding itself, it also blocks unrelated forwarding
arriving on that Wi-Fi to avoid opening a new router path. This may affect
future subnet-router use while the AP is running. Test those services
separately. The Rust supervisor listens to ip/iw/nft/logind event streams with a 30-second watchdog. The tray watches runtime status changes and refreshes on menu open and every 60 seconds. Neither is a packet-processing process. The service does not guarantee isolation if privileged external software flushes all firewall tables or modifies forwarding policies.
A full-tunnel VPN or kill switch may block Internet sharing or local
streaming. The status label reports a representative route, not Internet
reachability or a comprehensive VPN-policy check. Split-tunnel VPNs with
non-overlapping routes should remain compatible.

## Test checklist on Gram

1. Build and activate, verify existing Wi-Fi mode still works.
2. Start shared mode from tray; scan QR; check DHCP and Moonlight. Verify the legacy set is empty, Wi-Fi address cannot serve Moonlight, and the output chain's AP UDP source-port counters increase during streaming.
3. Inspect `sudo nft list table inet ipad_display`, `ip -4 rule`,
   `ip -4 route show table all`, `iw dev` (use nix shell for iw).
4. Connect UGA/homewg, test SSH to Sapelo/GPU from Gram, public Internet
   from iPad, and rejected VPN destination access from iPad.
5. Stop and inspect that ipad-ap is absent;
   verify original Wi-Fi forwarding and VPN routes are unchanged. The guard table remains installed with empty shared, owned_forward and legacy sets.
6. Test direct mode, suspend/resume, Wi-Fi channel change, firewall reload,
   and startup failure. Full-tunnel/VPN router compatibility is not tested.

System logs: `journalctl -u ipad-hotspot-wifi -u ipad-hotspot-direct -u ipad-hotspot-shared -b`.
User logs: `ipad-display logs`. Blue tray icon means services ready; green means a Wi-Fi station is authorized, not that Moonlight video or Internet connectivity has been verified. Amber indicates a transition, partial startup, failure or paused route.

Rust backend has no external crates. Nix builds and runs unit tests for channel parsing, width selection and route overlap. The full system still requires an on-device build and runtime validation. Host settings are declared in services.ipad-display; no secrets are stored in Nix or Git.
