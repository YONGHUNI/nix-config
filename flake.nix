{
  description = "Yonghun's NixOS configurations";

  inputs = {
    # Laptop: current NixOS release
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Preserve the existing WSL package version for now
    nixpkgs-wsl.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs-wsl";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    dotfiles = {
      url = "github:YONGHUNI/dotfiles";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-wsl,
      nixos-wsl,
      home-manager,
      plasma-manager,
      nix-flatpak,
      dotfiles,
      ...
    }:
    {
      nixosConfigurations = {
        # Existing WSL machine
        wsl = nixpkgs-wsl.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/wsl/configuration.nix
          ];
        };

        # LG Gram laptop
        gram = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./hosts/gram/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                inherit dotfiles;
              };

              # Preserve manually created files instead of failing.
              home-manager.backupFileExtension = "hm-backup";

              home-manager.users.yonghun = {
                imports = [
                  plasma-manager.homeModules.plasma-manager
                  ./home/yonghun.nix
                  ./hosts/gram/home.nix
                ];
              };
            }

            nix-flatpak.nixosModules.nix-flatpak
          ];
        };
      };
    };
}
