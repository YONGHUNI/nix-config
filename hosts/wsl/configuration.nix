{ config, lib, pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "yhsuh";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 7d";
  };

  # Use OpenSSH with Kerberos/GSSAPI support
  programs.ssh.package = pkgs.opensshWithKerberos;

  # Shell aliases
  programs.bash.shellAliases = {
    nrs = "sudo nixos-rebuild switch --flake ~/nix-config#nixos";
    nrt = "sudo nixos-rebuild test --flake ~/nix-config#nixos";
  };

  # System packages
  environment.systemPackages = with pkgs; [
    # Core
    vim
    tmux
    git
    gh
    htop
    tree
    jq
    wget
    unzip

    # Python
    python3
    pyright
    black

    # YAML
    yaml-language-server

    # Nix
    nil
    statix
    nixpkgs-fmt
  ];

  # Kerberos for MPCDF GSSAPI authentication
  security.krb5 = {
    enable = true;
    settings = {
      libdefaults = {
        default_realm = "IPP-GARCHING.MPG.DE";
        forwardable = true;
      };
      realms."IPP-GARCHING.MPG.DE" = {
        kdc = [
          "kerberos.rzg.mpg.de"
          "kerberos1.rzg.mpg.de"
          "kerberos2.rzg.mpg.de"
          "kerberos3.rzg.mpg.de"
        ];
        admin_server = "kerberos1.rzg.mpg.de";
        default_domain = "rzg.mpg.de";
      };
      domain_realm = {
        "mpcdf.mpg.de" = "IPP-GARCHING.MPG.DE";
        ".mpcdf.mpg.de" = "IPP-GARCHING.MPG.DE";
        "rzg.mpg.de" = "IPP-GARCHING.MPG.DE";
        ".rzg.mpg.de" = "IPP-GARCHING.MPG.DE";
        "ipp.mpg.de" = "IPP-GARCHING.MPG.DE";
        ".ipp.mpg.de" = "IPP-GARCHING.MPG.DE";
        "ipp-garching.mpg.de" = "IPP-GARCHING.MPG.DE";
        ".ipp-garching.mpg.de" = "IPP-GARCHING.MPG.DE";
      };
    };
  };

  system.stateVersion = "25.11";
}
