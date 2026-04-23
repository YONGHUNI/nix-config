{ config, lib, pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "yhsuh";

  programs.ssh.package = pkgs.opensshWithKerberos;

  programs.bash.shellAliases = {
    nrs = "sudo nixos-rebuild switch --flake ~/nix-config#nixos";
    nrt = "sudo nixos-rebuild test --flake ~/nix-config#nixos";
  };

  system.stateVersion = "25.11";
}
