{
  description = "Yonghun's NixOS configurations";

  inputs = {
    # Laptop: current NixOS release
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      nixpkgs-unstable,
      nixpkgs-wsl,
      nixos-wsl,
      home-manager,
      plasma-manager,
      nix-flatpak,
      dotfiles,
      ...
    }:
    let
      commonNixModule = {
        nixpkgs.config.allowUnfree = true;

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          auto-optimise-store = true;
        };
      };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      nixosConfigurations = {
        # Existing WSL machine
        wsl = nixpkgs-wsl.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            commonNixModule
            nixos-wsl.nixosModules.default
            ./hosts/wsl/configuration.nix
          ];
        };

        # LG Gram laptop
        gram = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            commonNixModule
            ./hosts/gram/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                inherit dotfiles;
                pkgsUnstable = import nixpkgs-unstable {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                };
              };

              # Preserve manually created files instead of failing.
              home-manager.backupFileExtension = "hm-backup";

              home-manager.users.yonghun = {
                imports = [
                  plasma-manager.homeModules.plasma-manager
                  ./home/common.nix
                  ./home/yonghun.nix
                  ./hosts/gram/home.nix
                ];
              };
            }
            nix-flatpak.nixosModules.nix-flatpak
          ];
        };
        nixos-research = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            commonNixModule
            ./hosts/nixos-research/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                inherit dotfiles;
              };

              home-manager.backupFileExtension = "hm-backup";

              home-manager.users.yonghun = {
                imports = [
                  ./home/common.nix
                ];

                home.username = "yonghun";
                home.homeDirectory = "/home/yonghun";
                home.stateVersion = "26.05";
              };
            }
          ];
        };
        nixos-dns = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            commonNixModule
            ./hosts/nixos-dns/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                inherit dotfiles;
              };

              home-manager.backupFileExtension = "hm-backup";

              home-manager.users.yonghun = {
                imports = [
                  ./home/common.nix
                ];

                home.username = "yonghun";
                home.homeDirectory = "/home/yonghun";
                home.stateVersion = "26.05";
              };
            }
          ];
        };

      };
    };
}
