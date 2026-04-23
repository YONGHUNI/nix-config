{
  description = "Nix Configuration (NixOS WSL + macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-wsl, nix-darwin, ... }: {

    # WSL: sudo nixos-rebuild switch --flake ~/nix-config#nixos
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        ./modules/common.nix
        ./hosts/wsl/default.nix
      ];
    };

    # macOS: darwin-rebuild switch --flake ~/nix-config#mac
    darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./modules/common.nix
        ./hosts/mac/default.nix
      ];
    };
  };
}
