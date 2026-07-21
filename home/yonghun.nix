{ pkgs, ... }:

let
  hop = pkgs.callPackage ../pkgs/hop { };

  toggleTouchpadLed = pkgs.writeShellScriptBin "toggle-touchpad-led" ''
    set -eu

    led="/sys/class/leds/tpad_led/brightness"

    if [ ! -e "$led" ]; then
      echo "Touchpad LED interface not found: $led" >&2
      exit 1
    fi

    if [ ! -w "$led" ]; then
      echo "Touchpad LED interface is not writable: $led" >&2
      exit 1
    fi

    case "$(${pkgs.coreutils}/bin/cat "$led")" in
      0)
        printf '1\n' > "$led"
        ;;
      1)
        printf '0\n' > "$led"
        ;;
      *)
        echo "Unexpected touchpad LED value" >&2
        exit 1
        ;;
    esac
  '';
in

{
  home.username = "yonghun";
  home.homeDirectory = "/home/yonghun";

  # Keep this value after initial installation.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.plasma = {
    enable = true;

    hotkeys.commands."toggle-touchpad-led" = {
      name = "Toggle touchpad LED";
      key = "F24";
      command = "${toggleTouchpadLed}/bin/toggle-touchpad-led";
    };
  };

  home.packages = with pkgs; [
    git
    gh
    htop
    bat
    wev
    hop
    toggleTouchpadLed
  ];

  # Fcitx5 input method list
  xdg.configFile."fcitx5/profile".text = ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=hangul

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=hangul
    Layout=

    [GroupOrder]
    0=Default
  '';
}
