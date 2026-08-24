{
  config,
  lib,
  pkgs,
  ...
}:

{
  wsl.enable = true;
  wsl.defaultUser = "yhsuh";

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 7d";
  };

  # Shell aliases
  programs.bash.shellAliases = {
    nrs = "sudo nixos-rebuild switch --flake ~/nix-config#wsl";
    nrt = "sudo nixos-rebuild test --flake ~/nix-config#wsl";
  };

  # General-purpose tools only. Project runtimes belong in project-local environments.
  environment.systemPackages = with pkgs; [
    vim
    tmux
    git
    gh
    htop
    tree
    jq
    wget
    unzip

    # Editor / lint tooling
    pyright
    black
    yaml-language-server
    nil
    statix
    nixpkgs-fmt
  ];

  system.stateVersion = "25.11";
}
