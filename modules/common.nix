{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System packages
  environment.systemPackages = with pkgs; [
    git
    gh
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
}
