{ modulesPath, pkgs, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  networking.hostName = "nixos-dns";

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

  system.stateVersion = "26.05";
}
