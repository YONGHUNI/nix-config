"""On-demand Gram AP. Root-only systemd service; never changes VPN routes/DNS."""
import grp
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import time

WIFI = "wlp0s20f3"
AP = "ipad-ap"
SSID = "Gram-Display"
HOST = "10.42.0.1"
CLIENT = "10.42.0.2"
NET = ipaddress.ip_network("10.42.0.0/24")
TABLE = "ipad_display"
RUN = Path("/run/ipad-hotspot")
STATE = Path("/var/lib/ipad-hotspot")
FORWARD = Path("/proc/sys/net/ipv4/conf") / WIFI / "forwarding"
children = []


def cmd(*args, check=True, data=None):
    return subprocess.run(args, check=check, input=data, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def exists():
    return Path("/sys/class/net", AP).exists()


def check_routes():
    for route in json.loads(cmd("ip", "-j", "-4", "route", "show", "table", "all").stdout):
        dst = route.get("dst", "default")
        if dst == "default" or route.get("dev") == AP:
            continue
        net = ipaddress.ip_network(dst, strict=False)
        # Default and split-default routes are not subnet ownership.
        if net.prefixlen > 1 and NET.overlaps(net):
            raise RuntimeError("Hotspot subnet overlaps an existing route: " + dst)


def channel():
    info = cmd("iw", "dev", WIFI, "info").stdout
    link = cmd("iw", "dev", WIFI, "link").stdout
    match = re.search(r"channel (\d+) \((\d+) MHz\), width: (\d+) MHz, center1: (\d+) MHz", info)
    if not match or "Connected to " not in link:
        raise RuntimeError("Connect the Gram to Wi-Fi before starting the hotspot.")
    return tuple(map(int, match.groups()))


def variants(ch, freq, width, center):
    # Same primary channel; never force a regulatory domain or bypass DFS.
    if 5000 <= freq < 5900:
        if width >= 80 and ch in (36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112,
                                  116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161):
            for start in (36, 52, 100, 116, 132, 149):
                if ch in range(start, start + 16, 4):
                    side = "+" if (ch - start) % 8 == 0 else "-"
                    yield f"ieee80211ac=1\nht_capab=[HT40{side}]\nvht_oper_chwidth=1\nvht_oper_centr_freq_seg0_idx={start+6}\n"
                    break
        if width >= 40:
            # In 5 GHz, 40 MHz pairs are fixed within each 80 MHz block.
            for start in (36, 52, 100, 116, 132, 149):
                if ch in range(start, start + 16, 4):
                    side = "+" if (ch - start) % 8 == 0 else "-"
                    yield f"ht_capab=[HT40{side}]\n"
                    break
        yield ""
    elif 2400 <= freq < 2500 and ch != 14:
        # Prefer reliable 20 MHz on crowded 2.4 GHz networks.
        yield ""
    else:
        raise RuntimeError("Unsupported upstream Wi-Fi frequency.")


def write_private(path, data):
    with path.open("w", encoding="ascii") as f:
        f.write(data)
    path.chmod(0o600)


def firewall(shared, owns_wifi_forwarding):
    # Separate base chains: ACCEPT here cannot override a later VPN DROP.
    outbound = ""
    if shared:
        outbound = f"""
        iifname "{AP}" oifname "{WIFI}" ip saddr {CLIENT} ct state {{ new, established, related }} counter accept
        iifname "{WIFI}" oifname "{AP}" ip daddr {CLIENT} ct state {{ established, related }} counter accept
        """
    unrelated = f'iifname "{WIFI}" oifname != "{AP}" counter drop' if owns_wifi_forwarding else ""
    nat = f"""
    chain nat {{
        type nat hook postrouting priority 99; policy accept;
        iifname "{AP}" oifname "{WIFI}" ip saddr {CLIENT} counter masquerade
    }}""" if shared else ""
    return f"""
table inet {TABLE} {{
    chain input {{
        type filter hook input priority -10; policy accept;
        iifname "{AP}" meta nfproto ipv4 udp sport 68 udp dport 67 counter accept
        iifname "{AP}" ip saddr {CLIENT} ip daddr {HOST} tcp dport {{ 47984, 47989, 48010 }} counter accept
        iifname "{AP}" ip saddr {CLIENT} ip daddr {HOST} udp dport {{ 47998, 47999, 48000, 48002, 48010 }} counter accept
        iifname "{AP}" ip saddr {CLIENT} ip daddr {HOST} icmp type echo-request counter accept
        iifname "{AP}" counter drop
    }}
    chain forward {{
        type filter hook forward priority -10; policy accept;
        iifname "{AP}" ip daddr {{ 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }} counter drop
        {outbound}
        iifname "{AP}" counter drop
        oifname "{AP}" counter drop
        {unrelated}
    }}
    {nat}
}}
"""


def stop_child(p):
    if p.poll() is None:
        p.terminate()
        try:
            p.wait(timeout=4)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()


def cleanup():
    # Markers are root-owned; do not touch a manually created AP or table.
    for p in reversed(children):
        stop_child(p)
    if (RUN / "owned-ap").exists():
        if exists():
            cmd("ip", "link", "set", AP, "down", check=False)
            cmd("iw", "dev", AP, "del", check=False)
        if exists():
            print("AP deletion failed; keeping isolation table", file=sys.stderr, flush=True)
            return
        (RUN / "owned-ap").unlink(missing_ok=True)
    if (RUN / "wifi-forward").exists():
        # Do not undo a global forwarding policy enabled by another service.
        if Path("/proc/sys/net/ipv4/ip_forward").read_text().strip() == "0" and FORWARD.exists():
            FORWARD.write_text("0\n")
        (RUN / "wifi-forward").unlink(missing_ok=True)
    if (RUN / "owned-table").exists():
        cmd("nft", "delete", "table", "inet", TABLE, check=False)
        (RUN / "owned-table").unlink(missing_ok=True)
    (RUN / "qr.txt").unlink(missing_ok=True)
    (RUN / "status.json").unlink(missing_ok=True)


def start(mode):
    shared = mode == "shared"
    os.umask(0o077)
    os.chown(RUN, 0, grp.getgrnam("wheel").gr_gid)
    RUN.chmod(0o750)
    if exists() or cmd("nft", "list", "table", "inet", TABLE, check=False).returncode == 0:
        raise RuntimeError("Existing manual AP or firewall table found; clean up first.")
    check_routes()
    initial = channel()
    ch, freq, width, center = initial
    password_file = STATE / "password"
    if not password_file.exists():
        write_private(password_file, secrets.token_hex(12))
    password = password_file.read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{24}", password):
        raise RuntimeError("Invalid stored hotspot password.")
    owns_wifi = shared and FORWARD.read_text().strip() == "0"
    (RUN / "owned-table").touch()
    cmd("nft", "-f", "-", data=firewall(shared, owns_wifi))
    (RUN / "owned-ap").touch()
    cmd("iw", "dev", WIFI, "interface", "add", AP, "type", "__ap")
    cmd("nmcli", "device", "set", AP, "managed", "no")
    cmd("ip", "link", "set", AP, "down")
    cmd("iw", "dev", AP, "set", "type", "__ap")
    Path(f"/proc/sys/net/ipv6/conf/{AP}/disable_ipv6").write_text("1\n")
    cmd("ip", "addr", "add", HOST + "/24", "dev", AP)
    hw = "a" if freq >= 5000 else "g"
    for extra in variants(ch, freq, width, center):
        config = f"""interface={AP}
driver=nl80211
ssid={SSID}
hw_mode={hw}
channel={ch}
ieee80211n=1
wmm_enabled=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase={password}
""" + extra
        conf = RUN / "hostapd.conf"
        write_private(conf, config)
        p = subprocess.Popen(["hostapd", str(conf)])
        children.append(p)
        for _ in range(30):
            if p.poll() is not None:
                break
            info = cmd("iw", "dev", AP, "info", check=False).stdout
            if f"ssid {SSID}" in info and "channel " in info and "type AP" in info:
                time.sleep(0.5)
                if p.poll() is None:
                    break
            time.sleep(0.2)
        else:
            info = ""
        if p.poll() is None and f"ssid {SSID}" in info and "channel " in info:
            break
        stop_child(p)
        cmd("ip", "link", "set", AP, "down", check=False)
        cmd("iw", "dev", AP, "set", "type", "__ap")
    else:
        raise RuntimeError("AP could not start on this Wi-Fi channel.")
    if shared:
        if owns_wifi:
            (RUN / "wifi-forward").touch()
            FORWARD.write_text("1\n")
        Path(f"/proc/sys/net/ipv4/conf/{AP}/forwarding").write_text("1\n")
    else:
        Path(f"/proc/sys/net/ipv4/conf/{AP}/forwarding").write_text("0\n")
    router = HOST if shared else ""
    dns = ",1.1.1.1,1.0.0.1" if shared else ""
    dhcp = subprocess.Popen([
        "dnsmasq", "--conf-file=/dev/null", "--keep-in-foreground", "--port=0",
        "--interface=" + AP, "--except-interface=lo", "--bind-interfaces",
        f"--dhcp-range={CLIENT},{CLIENT},255.255.255.0,12h",
        "--dhcp-option=option:router" + ("," + router if router else ""),
        "--dhcp-option=option:dns-server" + dns,
        "--leasefile-ro", "--log-dhcp"])
    children.append(dhcp)
    time.sleep(0.5)
    if dhcp.poll() is not None:
        raise RuntimeError("DHCP failed to start.")
    qr = RUN / "qr.txt"
    write_private(qr, f"WIFI:T:WPA;S:{SSID};P:{password};;")
    os.chown(qr, 0, grp.getgrnam("wheel").gr_gid)
    qr.chmod(0o640)
    status = RUN / "status.json"
    def report():
        info = cmd("iw", "dev", AP, "info").stdout
        line = next((l.strip() for l in info.splitlines() if "channel " in l), "")
        route = cmd("ip", "-4", "route", "get", "1.1.1.1", "from", CLIENT, "iif", AP, check=False)
        internet = shared and route.returncode == 0 and bool(re.search(r"\bdev " + WIFI + r"\b", route.stdout))
        tmp = RUN / "status.tmp"
        tmp.write_text(json.dumps({"mode": mode, "ssid": SSID, "ip": HOST, "channel": line,
                                   "internet": "route-available" if internet else "paused" if shared else "off"}))
        tmp.chmod(0o644)
        tmp.replace(status)
    report()
    cmd("systemd-notify", "--ready")
    while True:
        time.sleep(2)
        if any(p.poll() is not None for p in (children[-2], children[-1])):
            raise RuntimeError("AP or DHCP exited.")
        if cmd("nft", "list", "table", "inet", TABLE, check=False).returncode:
            raise RuntimeError("Isolation table disappeared; stopping AP.")
        check_routes()
        if channel() != initial:
            raise RuntimeError("Upstream channel changed; restart hotspot to reselect channel.")
        # Stop on logout, but keep the AP when the desktop is locked.
        sessions = cmd("loginctl", "list-sessions", "--no-legend", "--no-pager").stdout.splitlines()
        local_gui = False
        for line in sessions:
            if not line.split():
                continue
            props = cmd("loginctl", "show-session", line.split()[0], "-p", "Type", "-p", "Remote", "-p", "State", check=False).stdout
            if ("Type=wayland" in props or "Type=x11" in props) and "Remote=no" in props and "State=closing" not in props:
                local_gui = True
                break
        if not local_gui:
            return
        report()


def terminate(signum, frame):
    raise SystemExit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    if sys.argv[1:] == ["cleanup"]:
        cleanup()
    elif sys.argv[1:] in (["direct"], ["shared"]):
        try:
            start(sys.argv[1])
        except (RuntimeError, OSError, subprocess.SubprocessError) as e:
            # Do not log command output or secrets.
            print(f"ipad-hotspot: {e}", file=sys.stderr, flush=True)
            sys.exit(1)
        finally:
            cleanup()
    else:
        sys.exit("Usage: ipad-hotspot direct|shared|cleanup")
