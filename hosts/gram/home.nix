{ pkgs, ... }:

let
  syncTouchpadLed = pkgs.writeShellScriptBin "sync-touchpad-led" ''
    set -eu

    led="/sys/class/leds/tpad_led/brightness"
    manager="/org/kde/KWin/InputDevice"
    manager_interface="org.kde.KWin.InputDeviceManager"
    device_interface="org.kde.KWin.InputDevice"

    ${pkgs.coreutils}/bin/sleep 0.1

    if [ ! -e "$led" ]; then
      echo "Touchpad LED interface not found: $led" >&2
      exit 1
    fi

    if [ ! -w "$led" ]; then
      echo "Touchpad LED interface is not writable: $led" >&2
      exit 1
    fi

    devices="$(
      ${pkgs.systemd}/bin/busctl --user get-property \
        org.kde.KWin \
        "$manager" \
        "$manager_interface" \
        devicesSysNames
    )"

    touchpad_device=""

    for sysname in $(
      printf '%s\n' "$devices" \
        | ${pkgs.gnused}/bin/sed -E 's/^as [0-9]+ //' \
        | ${pkgs.coreutils}/bin/tr ' ' '\n' \
        | ${pkgs.coreutils}/bin/tr -d '"'
    ); do
      device="$manager/$sysname"

      is_touchpad="$(
        ${pkgs.systemd}/bin/busctl --user get-property \
          org.kde.KWin \
          "$device" \
          "$device_interface" \
          touchpad 2>/dev/null || true
      )"

      if [ "$is_touchpad" = "b true" ]; then
        touchpad_device="$device"
        break
      fi
    done

    if [ -z "$touchpad_device" ]; then
      echo "No touchpad device found through KWin" >&2
      exit 1
    fi

    state="$(
      ${pkgs.systemd}/bin/busctl --user get-property \
        org.kde.KWin \
        "$touchpad_device" \
        "$device_interface" \
        enabled
    )"

    case "$state" in
      "b true")
        # Touchpad enabled: indicator on
        printf '1\n' > "$led"
        ;;
      "b false")
        # Touchpad disabled: indicator off
        printf '0\n' > "$led"
        ;;
      *)
        echo "Unexpected touchpad state: $state" >&2
        exit 1
        ;;
    esac
  '';
in
{
  programs.plasma = {
    enable = true;

    hotkeys.commands."sync-touchpad-led" = {
      name = "Sync touchpad LED";
      key = "F24";
      command = "${syncTouchpadLed}/bin/sync-touchpad-led";
    };
  };

  home.packages = [
    syncTouchpadLed
  ];
}
