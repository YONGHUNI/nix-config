{ pkgs, ... }:

let
  hop = pkgs.callPackage ../pkgs/hop { };
in
{
  home.username = "yonghun";
  home.homeDirectory = "/home/yonghun";

  # Keep this value after initial installation.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    git
    gh
    htop
    bat
    wev
    hop
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
