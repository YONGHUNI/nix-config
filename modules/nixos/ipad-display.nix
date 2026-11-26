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

  ipadDisplay = pkgs.writeShellApplication {
    name = "ipad-display";
    runtimeInputs = [
      pkgs.systemd
      pkgs.iproute2
      pkgs.networkmanager
      pkgs.gawk
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

      start_display() {
        if ! systemctl --user is-active --quiet graphical-session.target; then
          echo "Run this command inside your Plasma desktop session." >&2
          return 1
        fi
        if ! systemctl --user start sunshine.service; then
          systemctl --user stop ipad-virtual-monitor.service || true
          echo "Startup failed. Run ipad-display logs." >&2
          return 1
        fi
        echo "Sunshine service started. Open Moonlight to connect."
        print_network
      }

      stop_display() {
        systemctl --user stop sunshine.service ipad-virtual-monitor.service
      }

      case "''${1:-}" in
        start|stop|restart|toggle)
          exec 9>"''${XDG_RUNTIME_DIR:?}/ipad-display.lock"
          flock 9
          case "$1" in
            start) start_display ;;
            stop) stop_display ;;
            restart) stop_display; start_display ;;
            toggle)
              state_info
              if [[ "$server" == active || "$monitor" == active ]]; then
                stop_display
              else
                start_display
              fi
              ;;
          esac
          ;;
        info)
          network_info
          state_info
          jq -n --arg ssid "$ssid" --arg ipv4 "$ipv4" \
            --arg server "$server" --arg monitor "$monitor" \
            '{ssid:$ssid,ipv4:$ipv4,sunshine:$server,monitor:$monitor}'
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
