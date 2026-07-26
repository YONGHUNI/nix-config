{ pkgs, ... }:

{
  # Provide Nerd Fonts for terminal prompts
  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
    ];

    fontconfig.defaultFonts.monospace = [
      "JetBrainsMono Nerd Font"
    ];
  };

  # Provide location information to applications on laptops.
  location.provider = "geoclue2";

  services.geoclue2 = {
    enable = true;
    enableWifi = true;

    # Disable location sources not used on ordinary laptops.
    enableNmea = false;
    enable3G = false;
    enableCDMA = false;
    enableModemGPS = false;

    # Do not contribute nearby Wi-Fi information.
    submitData = false;
  };


  services.automatic-timezoned.enable = true;
}
