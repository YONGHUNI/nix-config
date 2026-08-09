{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # UEFI boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Host identity / networking
  networking.hostName = "nixos-research";
  networking.networkmanager.enable = true;

  # Remote access
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = false;

  # NVIDIA GPU
  boot.blacklistedKernelModules = [ "nouveau" ];
  #nixpkgs.config.allowUnfree = true;
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
  };

  # Persistent data disk
  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/5d533a52-7f82-4b6a-8a5a-bd163f50f482";
    fsType = "ext4";
    options = [
      "defaults"
      "discard"
    ];
  };

  # Proxmox guest integration
  services.qemuGuest.enable = true;

  # Main user
  users.users.yonghun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # Basic administrative tools only
  environment.systemPackages = with pkgs; [
    git
    vim
    tmux
    curl
  ];

  # We will use flakes for system/project configuration.
  #  nix.settings.experimental-features = [
  #    "nix-command"
  #    "flakes"
  #  ];

  system.stateVersion = "26.05";
}
