{
  description = "Home-AI & Smart-Home Server Workstation (NixOS)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.home-ai-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/server/hardware.nix
        ./hosts/server/configuration.nix
        ./modules/desktop.nix
        ./modules/ai-services.nix
      ];
    };
  };
}
