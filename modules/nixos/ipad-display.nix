{ config, lib, pkgs, ... }:

let
  cfg = config.services.ipad-display;
  displayName = "iPad";
  outputName = "Virtual-${displayName}";
  resolution = cfg.resolution;
  scale = cfg.scale;
  wifiInterface = cfg.upstreamInterface;
  host = "${cfg.prefix}.1";
  client = "${cfg.prefix}.2";
  kscreenDoctor = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor";

  krfbStart = pkgs.writeShellScript "ipad-virtual-monitor" ''
    set -e
    exec ${pkgs.kdePackages.krfb}/bin/krfb-virtualmonitor \
      --name ${displayName} \
      --resolution ${resolution} \
      --password "$(${pkgs.openssl}/bin/openssl rand -hex 4)" \
      --port 5905
  '';

  waitForDisplay = pkgs.writeShellScript "ipad-wait-for-display" ''
    set -e
    for ((attempt = 0; attempt < 40; attempt++)); do
      if outputs="$(${kscreenDoctor} -o)" && ${pkgs.gnugrep}/bin/grep -Fq ' ${outputName} ' <<< "$outputs"; then
        ${kscreenDoctor} \
          output.${outputName}.mirror.none \
          output.${outputName}.scale.${scale}
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.5
    done
    echo "Failed to create ${outputName}." >&2
    exit 1
  '';

  hotspot = pkgs.callPackage ../../pkgs/ipad-hotspotd { };

  ipadDisplay = pkgs.writeShellApplication {
    name = "ipad-display";
    runtimeInputs = [
      pkgs.systemd
      pkgs.iproute2
      pkgs.networkmanager
      pkgs.gawk
      pkgs.qrencode
      pkgs.jq
      pkgs.util-linux
      pkgs.kdePackages.libkscreen
    ];
    text = ''
      network_info() {
        ssid="$(LC_ALL=C nmcli -t -e no -f IN-USE,SSID device wifi list ifname ${wifiInterface} --rescan no 2>/dev/null | awk 'substr($0,1,2)=="*:" {print substr($0,3); exit}' || true)"
        ipv4="$(ip -4 -o addr show dev ${wifiInterface} scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)"
      }

      state_info() {
        server="$(systemctl --user show -p ActiveState --value sunshine.service 2>/dev/null || true)"
        monitor="$(systemctl --user show -p ActiveState --value ipad-virtual-monitor.service 2>/dev/null || true)"
      }

      print_network() {
        network_info
        printf 'Wi-Fi SSID: %s\nWi-Fi IPv4: %s\n' "''${ssid:-Not connected}" "''${ipv4:-Unavailable}"
      }

      hotspot_stop() {
        for unit in ipad-hotspot-wifi.service ipad-hotspot-direct.service ipad-hotspot-shared.service; do
          systemctl stop "$unit" || return 1
        done
      }

      start_display() {
        if ! systemctl --user is-active --quiet graphical-session.target; then
          echo "Run this command inside your Plasma desktop session." >&2
          return 1
        fi
        mode="''${1:-${cfg.defaultMode}}"
        case "$mode" in wifi|direct|shared) ;; *) return 1 ;; esac
        # Never carry an existing stream across a connection-mode change.
        systemctl --user stop sunshine.service ipad-virtual-monitor.service || return 1
        hotspot_stop || return 1
        printf "%s\n" "$mode" > "$XDG_RUNTIME_DIR/ipad-display-mode"
        systemctl start "ipad-hotspot-$mode.service" || return 1
        if ! systemctl --user start sunshine.service; then
          hotspot_stop || true
          systemctl --user stop ipad-virtual-monitor.service || true
          echo "Startup failed. Run ipad-display logs." >&2
          return 1
        fi
        echo "Sunshine service started. Open Moonlight to connect."
        if [[ "$mode" != wifi ]]; then
          echo "Hotspot: ${cfg.ssid}; Moonlight host: ${host}"
        fi
        print_network
      }

      stop_display() {
        systemctl --user stop sunshine.service ipad-virtual-monitor.service
        hotspot_stop || return 1
        rm -f "$XDG_RUNTIME_DIR/ipad-display-mode"
      }

      case "''${1:-}" in
        start|stop|restart|toggle)
          exec 9>"''${XDG_RUNTIME_DIR:?}/ipad-display.lock"
          flock 9
          case "$1" in
            start) start_display "''${2:-${cfg.defaultMode}}" ;;
            stop) stop_display ;;
            restart) stop_display; start_display "''${2:-${cfg.defaultMode}}" ;;
            toggle)
              state_info
              if [[ "$server" == active || "$monitor" == active ]] ||
                 systemctl is-active --quiet ipad-hotspot-wifi.service ||
                 systemctl is-active --quiet ipad-hotspot-direct.service ||
                 systemctl is-active --quiet ipad-hotspot-shared.service; then
                stop_display
              else
                start_display "''${2:-${cfg.defaultMode}}"
              fi
              ;;
          esac
          ;;
        info)
          network_info
          state_info
          jq -n --arg ssid "$ssid" --arg ipv4 "$ipv4" \
            --arg server "$server" --arg monitor "$monitor" \
            --argjson hotspot "$(cat /run/ipad-hotspot/status.json 2>/dev/null || echo null)" \
            --arg wifi "$(systemctl show -p ActiveState --value ipad-hotspot-wifi.service)" \
            --arg direct "$(systemctl show -p ActiveState --value ipad-hotspot-direct.service)" \
            --arg shared "$(systemctl show -p ActiveState --value ipad-hotspot-shared.service)" \
            --arg requested "$(cat "$XDG_RUNTIME_DIR/ipad-display-mode" 2>/dev/null || echo wifi)" \
            '{ssid:$ssid,ipv4:$ipv4,sunshine:$server,monitor:$monitor,hotspot:$hotspot,wifi:$wifi,direct:$direct,shared:$shared,requested:$requested}'
          ;;
        qr)
          test -r /run/ipad-hotspot/qr.txt
          qrencode -r /run/ipad-hotspot/qr.txt -o - -s 8 -m 4
          ;;
        status)
          print_network
          cat /run/ipad-hotspot/status.json 2>/dev/null || true
          systemctl --user --no-pager status sunshine.service ipad-virtual-monitor.service || true
          kscreen-doctor -o
          ;;
        logs)
          journalctl --user -u sunshine.service -u ipad-virtual-monitor.service -f
          ;;
        *)
          echo "Usage: ipad-display {start|restart|toggle} [wifi|direct|shared], or {stop|status|info|logs|qr}" >&2
          exit 1
          ;;
      esac
    '';
  };

  tray = pkgs.kdePackages.callPackage ../../pkgs/ipad-display { inherit ipadDisplay; inherit (cfg) defaultMode; };
in
{
  # Nixpkgs 0dc498b's wpa_supplicant module queues a global restart on
  # every WLAN add/remove, even when NetworkManager controls it over D-Bus.
  # Extend the merged udev option with a narrow predicate on that rule.
  # RUN-= is not supported by systemd; do not reset unrelated RUN actions.
  options.services.udev.extraRules = lib.mkOption {
    apply = rules:
      if cfg.enable then
        builtins.replaceStrings
          [ ''RUN+="/run/current-system/systemd/bin/systemctl try-restart wpa_supplicant.service"'' ]
          [ ''KERNEL!="ipad-ap", RUN+="/run/current-system/systemd/bin/systemctl try-restart wpa_supplicant.service"'' ]
          rules
      else rules;
  };

  options.services.ipad-display = {
    enable = lib.mkEnableOption "Gram wireless iPad display";
    resolution = lib.mkOption { type = lib.types.strMatching "[0-9]+x[0-9]+"; default = "2732x2048"; };
    scale = lib.mkOption { type = lib.types.strMatching "[0-9]+([.][0-9]+)?"; default = "1.5"; };
    upstreamInterface = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_.-]+"; default = "wlp0s20f3"; };
    ssid = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_-]{1,32}"; default = "Gram-Display"; };
    prefix = lib.mkOption { type = lib.types.strMatching "[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}"; default = "10.42.0"; description = "First three octets of private /24 hotspot network."; };
    defaultMode = lib.mkOption { type = lib.types.enum [ "wifi" "direct" "shared" ]; default = "shared"; };
  };
  config = lib.mkIf cfg.enable {
  # The AP is explicitly unmanaged; the upstream connection stays under NM.
  networking.networkmanager.unmanaged = [ "interface-name:ipad-ap" ];


  networking.firewall.interfaces."ipad-ap" = {
    allowedTCPPorts = [ 47984 47989 48010 ];
    allowedUDPPorts = [ 67 47998 47999 48000 48002 48010 ];
  };

  # Authorize only start/stop of the three display mode units for local wheel users.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.local && subject.active && subject.isInGroup("wheel") &&
          ["ipad-hotspot-wifi.service", "ipad-hotspot-direct.service", "ipad-hotspot-shared.service"].indexOf(action.lookup("unit")) >= 0 &&
          ["start", "stop"].indexOf(action.lookup("verb")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  # Independent restrictive base chains, installed before an AP can start.
  # Keep the existing NixOS iptables backend and VPN rules untouched.
  systemd.tmpfiles.rules = [ "d /run/ipad-hotspot 0750 root wheel -" ];
  systemd.services = {
    ipad-hotspot-guard = {
      description = "Default-deny iPad hotspot network policy";
      wantedBy = [ "multi-user.target" ];
      before = [ "ipad-hotspot-wifi.service" "ipad-hotspot-direct.service" "ipad-hotspot-shared.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.nftables ];
      script = ''
        # Replace atomically, including on rebuild. An empty set denies sharing.
        nft -f - <<'EOF'
        table inet ipad_display
        delete table inet ipad_display
        table inet ipad_display {
          set shared { type ifname; }
          set legacy { type ifname; }
          set owned_forward { type ifname; }
          chain input {
            type filter hook input priority -10; policy accept;
            iifname "ipad-ap" meta nfproto ipv4 udp sport 68 udp dport 67 accept
            iifname "ipad-ap" ip saddr ${client} ip daddr ${host} tcp dport { 47984, 47989, 48010 } accept
            iifname "ipad-ap" ip saddr ${client} ip daddr ${host} udp dport { 47998, 47999, 48000, 48002, 48010 } accept
            iifname "ipad-ap" ip saddr ${client} ip daddr ${host} icmp type echo-request accept
            iifname "ipad-ap" counter drop
            # Sunshine streaming ports are closed unless explicit legacy mode is active.
            iifname "lo" accept
            iifname @legacy tcp dport { 47984, 47989, 48010 } accept
            iifname @legacy udp dport { 47998, 47999, 48000, 48002, 48010 } accept
            tcp dport { 47984, 47989, 48010 } counter drop
            udp dport { 47998, 47999, 48000, 48002, 48010 } counter drop
          }
          chain output {
            type filter hook output priority -10; policy accept;
            # Prevent residual stream packets from leaving via the old LAN.
            oifname "lo" accept
            oifname "ipad-ap" ip saddr ${host} ip daddr ${client} accept
            oifname @legacy accept
            tcp sport { 47984, 47989, 48010 } counter drop
            udp sport { 47998, 47999, 48000, 48002, 48010 } counter drop
          }
          chain forward {
            type filter hook forward priority -10; policy accept;
            iifname "ipad-ap" ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 } counter drop
            iifname @shared oifname "${wifiInterface}" ip saddr ${client} ct state { new, established, related } counter accept
            iifname "${wifiInterface}" oifname @shared ip daddr ${client} ct state { established, related } counter accept
            iifname "ipad-ap" counter drop
            oifname "ipad-ap" counter drop
            iifname @owned_forward oifname != "ipad-ap" counter drop
          }
          chain nat {
            type nat hook postrouting priority 99; policy accept;
            oifname "${wifiInterface}" ip saddr ${client} iifname @shared counter masquerade
          }
        }
        EOF
      '';
    };
  } // builtins.listToAttrs (map (mode: {
    name = "ipad-hotspot-${mode}";
    value = {
      description = "Gram iPad hotspot (${mode})";
      after = [ "NetworkManager.service" "firewall.service" "ipad-hotspot-guard.service" "systemd-tmpfiles-setup.service" ];
      requires = [ "NetworkManager.service" "firewall.service" "ipad-hotspot-guard.service" ];
      partOf = [ "ipad-hotspot-guard.service" ];
      path = with pkgs; [ iw iproute2 nftables hostapd dnsmasq systemd coreutils ];
      environment = {
        IPAD_UPSTREAM = wifiInterface;
        IPAD_SSID = cfg.ssid;
        IPAD_PREFIX = cfg.prefix;
        LC_ALL = "C";
      };
      conflicts = (map (other: "ipad-hotspot-${other}.service") (lib.filter (other: other != mode) [ "wifi" "direct" "shared" ])) ++ [ "sleep.target" ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${hotspot}/bin/ipad-hotspotd ${mode}";
        ExecStopPost = "${hotspot}/bin/ipad-hotspotd ${if mode == "wifi" then "wifi-cleanup" else "cleanup"}";
        UMask = "0077";
        StateDirectory = "ipad-hotspot";
        StateDirectoryMode = "0700";
        TimeoutStartSec = 60;
        TimeoutStopSec = 30;
        KillMode = "control-group";
      };
    };
  }) [ "wifi" "direct" "shared" ]);

  environment.systemPackages = [
    pkgs.kdePackages.krfb
    ipadDisplay
    tray
  ];

  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = false;
    openFirewall = false;

    # Credentials and paired clients remain in Sunshine's local app data.
    settings = {
      capture = "kwin";
      encoder = "vaapi";
      output_name = outputName;
      stream_audio = "disabled";
      upnp = "disabled";
      origin_web_ui_allowed = "pc";
    };
  };

  # The independent guard above restricts these ports to explicit legacy mode.
  # Keep the base firewall permits; an earlier guard DROP cannot be overridden.
  networking.firewall.interfaces.${wifiInterface} = {
    allowedTCPPorts = [
      47984
      47989
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48002
      48010
    ];
  };

  systemd.user.services.ipad-virtual-monitor = {
    description = "KDE virtual display for iPad";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "simple";
      ExecStart = krfbStart;
      ExecStartPost = waitForDisplay;
      TimeoutStartSec = 30;
    };
  };

  systemd.user.services.sunshine = {
    bindsTo = [ "ipad-virtual-monitor.service" ];
    after = [ "ipad-virtual-monitor.service" ];
  };

  systemd.user.services.ipad-display-tray = {
    description = "iPad Display system tray";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${tray}/bin/ipad-display-tray";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
  };
}
