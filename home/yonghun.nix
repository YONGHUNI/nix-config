{ pkgs, dotfiles, ... }:

let
  hop = pkgs.callPackage ../pkgs/hop { };

  kakaoClipboardFix = pkgs.writeShellApplication {
    name = "kakao-clipboard-fix";

    runtimeInputs = with pkgs; [
      imagemagick
      wl-clipboard
      gnugrep
    ];

    text = ''
      if ! wl-paste --list-types | grep -qx 'image/bmp'; then
        echo "KakaoTalk image/bmp data was not found in the clipboard." >&2
        exit 1
      fi

      wl-paste --type image/bmp \
        | magick bmp:- png:- \
        | wl-copy --type image/png
    '';
  };
in
{
  home.username = "yonghun";
  home.homeDirectory = "/home/yonghun";

  # Keep this value after initial installation.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.file = {
    ".bashrc".source = "${dotfiles}/.bashrc";
    ".vimrc".source = "${dotfiles}/.vimrc";
    ".tmux.conf".source = "${dotfiles}/.tmux.conf";
    ".Rprofile".source = "${dotfiles}/.Rprofile";
  };

  home.packages = with pkgs; [
    git
    gh
    htop
    bat
    wev
    hop
    kakaoClipboardFix
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
