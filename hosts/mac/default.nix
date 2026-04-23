{ config, lib, pkgs, ... }:

{
  # nix-darwin uses nixbuild instead of nixos-rebuild
  environment.shellAliases = {
    nrs = "darwin-rebuild switch --flake ~/nix-config#mac";
  };

  # macOS system defaults (optional, customize as needed)
  system.defaults.dock.autohide = true;
  system.defaults.finder.AppleShowAllExtensions = true;

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  programs.bash.enable = true;
}
