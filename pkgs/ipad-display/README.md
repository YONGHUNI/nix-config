# iPad wireless display (Gram)

KDE Wayland + Krfb + Sunshine + Moonlight. Native 2732x2048, scale 150%.
The tray runs with the Plasma session; streaming is on demand. Left-click
the tablet icon to toggle; right-click for service status, actual Wi-Fi SSID,
IPv4, IP copy, and local Sunshine web UI. If hidden, set iPad Display to
Always Shown in Plasma's System Tray settings.

CLI: `ipad-display start|stop|restart|toggle|status|info|logs`.
`info` emits JSON for the tray. A green icon means both services are active,
not that an iPad is connected or video has been verified.

Before the first migration, stop Moonlight, stop the old Sunshine service,
stop the manually launched krfb-virtualmonitor (Ctrl+C), and back up the
local Sunshine config directory. The module does not reset credentials,
certificates, or paired clients. Configuration is declarative; Moonlight
resolution/bitrate remain client-side. After rebuild, log in again or run
`systemctl --user start ipad-display-tray.service`.

Firewall: tested streaming ports are allowed on wlp0s20f3 on all Wi-Fi
networks; no new web UI/VNC port is opened. Prefer trusted networks.
UPnP is disabled. The stream and virtual monitor stop with the graphical
session. Build and test on Gram before relying on this configuration.
