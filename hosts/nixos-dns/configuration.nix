{
  modulesPath,
  pkgs,
  lib,
  ...
}:

let
  localHosts = {
    "router.home.arpa" = "192.168.0.1";
    "pve.home.arpa" = "192.168.0.200";
    "gpu.home.arpa" = "192.168.0.201";
    "dns.home.arpa" = "192.168.0.202";
  };
in
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  networking.hostName = "nixos-dns";

  networking.firewall = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [
      53
      3000
    ];
  };

  services.openssh = {
    enable = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users.yonghun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIoIx6gg+hqRjRV1lRCyOAVIPSC/sEIoddUAgElcC/Tv dydgns0556@gmail.com"
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
  ];

  services.adguardhome = {
    enable = true;

    host = "0.0.0.0";
    port = 3000;

    openFirewall = true;

    settings = {
      dns = {
        bind_hosts = [ "192.168.0.202" ];
        port = 53;

        upstream_dns = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        rewrites_enabled = true;

        rewrites = lib.mapAttrsToList (domain: answer: {
          inherit domain answer;
          enabled = true;
        }) localHosts;
      };
    };
  };

  system.stateVersion = "26.05";
}
