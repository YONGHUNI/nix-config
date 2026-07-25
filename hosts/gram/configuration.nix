# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    ../../modules/nixos/laptop.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-502dd682-dcf9-4c70-afb1-1846fb3419ff".device =
    "/dev/disk/by-uuid/502dd682-dcf9-4c70-afb1-1846fb3419ff";

  boot.initrd.luks.devices."luks-502dd682-dcf9-4c70-afb1-1846fb3419ff".crypttabExtraOpts = [
    "tpm2-device=auto"
  ];

  boot.initrd.luks.devices."luks-eb0f59b8-f70c-4ee3-991b-4dc7f4ca0256".crypttabExtraOpts = [
    "tpm2-device=auto"
  ];

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Seoul";

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      addons = with pkgs; [
        fcitx5-hangul
      ];
      waylandFrontend = true;
    };
  };
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  #   i18n.extraLocaleSettings = {
  #    LC_ADDRESS = "ko_KR.UTF-8";
  #    LC_IDENTIFICATION = "ko_KR.UTF-8";
  #    LC_MEASUREMENT = "ko_KR.UTF-8";
  #    LC_MONETARY = "ko_KR.UTF-8";
  #    LC_NAME = "ko_KR.UTF-8";
  #    LC_NUMERIC = "ko_KR.UTF-8";
  #    LC_PAPER = "ko_KR.UTF-8";
  #    LC_TELEPHONE = "ko_KR.UTF-8";
  #    LC_TIME = "ko_KR.UTF-8";
  #  };

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "korean:ralt_hangul,korean:rctrl_hanja";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."yonghun" = {
    isNormalUser = true;
    description = "Yonghun Suh";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    tree
    zoom-us
    git
    htop
    fastfetch

  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Remap the LG Fn+F5 hotkey from KEY_F21 to F24.
  services.udev.extraHwdb = ''
    evdev:name:LG WMI hotkeys:*
     KEYBOARD_KEY_74=f24
  '';

  # Allow members of the users group to control the touchpad LED.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chgrp users /sys%p/brightness"
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/brightness"
  '';

  # Enable the flatpak
  services.flatpak = {
    enable = true;

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];

    packages = [
      "com.usebottles.bottles"
    ];

    update.auto.enable = false;
    uninstallUnmanaged = false;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
