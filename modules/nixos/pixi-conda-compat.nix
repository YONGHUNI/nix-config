{ pkgs, ... }:

{
  # Allow generic dynamically linked Linux binaries from Pixi/Conda to run on NixOS.
  programs.nix-ld.enable = true;

  # conda-forge R currently assumes /usr/bin/which exists during startup.
  # NixOS provides which through the system profile instead of the FHS path.
  systemd.tmpfiles.rules = [
    "d /usr/bin 0755 root root -"
    "L+ /usr/bin/which - - - - ${pkgs.which}/bin/which"
  ];
}
