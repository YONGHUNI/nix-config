{ pkgs, ... }:

let
  displayName = "iPad";
  outputName = "Virtual-${displayName}";
  resolution = "2732x2048";
  scale = "1.5";
  wifiInterface = "wlp0s20f3";
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

  hotspot = pkgs.writeShellApplication {
    name = "ipad-hotspot-service";
    runtimeInputs = with pkgs; [ python3 iw iproute2 networkmanager nftables hostapd dnsmasq systemd ];
    text = ''
      exec python3 ${../../pkgs/ipad-display/hotspot.py} "$@"
    '';
  };

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
        systemctl stop ipad-hotspot-direct.service ipad-hotspot-shared.service
      }

      start_display() {
        if ! systemctl --user is-active --quiet graphical-session.target; then
          echo "Run this command inside your Plasma desktop session." >&2
          return 1
        fi
        mode="''${1:-wifi}"
        case "$mode" in
          wifi) ;;
          direct|shared)
            hotspot_stop
            systemctl start "ipad-hotspot-$mode.service" || return 1
            ;;
          *) return 1 ;;
        esac
        if ! systemctl --user start sunshine.service; then
          hotspot_stop || true
          systemctl --user stop ipad-virtual-monitor.service || true
          echo "Startup failed. Run ipad-display logs." >&2
          return 1
        fi
        echo "Sunshine service started. Open Moonlight to connect."
        print_network
      }

      stop_display() {
        systemctl --user stop sunshine.service ipad-virtual-monitor.service
        hotspot_stop
      }

      case "''${1:-}" in
        start|stop|restart|toggle)
          exec 9>"''${XDG_RUNTIME_DIR:?}/ipad-display.lock"
          flock 9
          case "$1" in
            start) start_display "''${2:-wifi}" ;;
            stop) stop_display ;;
            restart) stop_display; start_display "''${2:-wifi}" ;;
            toggle)
              state_info
              if [[ "$server" == active || "$monitor" == active ]]; then
                stop_display
              else
                start_display "''${2:-wifi}"
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
            '{ssid:$ssid,ipv4:$ipv4,sunshine:$server,monitor:$monitor,hotspot:$hotspot}'
          ;;
        qr)
          test -r /run/ipad-hotspot/qr.txt
          qrencode -r /run/ipad-hotspot/qr.txt -o - -s 8 -m 4
          ;;
        status)
          print_network
          systemctl --user --no-pager status sunshine.service ipad-virtual-monitor.service || true
          kscreen-doctor -o
          ;;
        logs)
          journalctl --user -u sunshine.service -u ipad-virtual-monitor.service -f
          ;;
        *)
          echo "Usage: ipad-display {start|stop|restart|toggle|status|info|logs}" >&2
          exit 1
          ;;
      esac
    '';
  };

  tray = pkgs.kdePackages.callPackage ../../pkgs/ipad-display { inherit ipadDisplay; };
in
{
  # The AP is explicitly unmanaged; the upstream connection stays under NM.
  networking.networkmanager.unmanaged = [ "interface-name:ipad-ap" ];
  networking.firewall.interfaces."ipad-ap" = {
    allowedTCPPorts = [ 47984 47989 48010 ];
    allowedUDPPorts = [ 67 47998 47999 48000 48002 48010 ];
  };

  # Authorize only start/stop of these two units for active local wheel users.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.local && subject.active && subject.isInGroup("wheel") &&
          ["ipad-hotspot-direct.service", "ipad-hotspot-shared.service"].indexOf(action.lookup("unit")) >= 0 &&
          ["start", "stop"].indexOf(action.lookup("verb")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  systemd.services = builtins.listToAttrs (map (mode: {
    name = "ipad-hotspot-${mode}";
    value = {
      description = "Gram iPad hotspot (${mode})";
      after = [ "NetworkManager.service" "firewall.service" ];
      requires = [ "NetworkManager.service" "firewall.service" ];
      conflicts = [ "ipad-hotspot-${if mode == "direct" then "shared" else "direct"}.service" "sleep.target" ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${hotspot}/bin/ipad-hotspot-service ${mode}";
        ExecStopPost = "${hotspot}/bin/ipad-hotspot-service cleanup";
        RuntimeDirectory = "ipad-hotspot";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "ipad-hotspot";
        StateDirectoryMode = "0700";
        TimeoutStartSec = 60;
        TimeoutStopSec = 30;
        KillMode = "mixed";
      };
    };
  }) [ "direct" "shared" ]);

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

  # Preserve the tested Wi-Fi-only rules; do not expose VNC or the web UI.
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
}
