{
  description = "NixOS config for svetos (BSPWM, NVIDIA, Btrfs+LUKS, RAID0 /home, Home Manager)";

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9P90lC9GO5RZcXcbYwvjw4rHczhBtpR1YwL+8="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    astronvim.url = "github:AstroNvim/AstroNvim";
    astronvim.flake = false; # берём как исходники
  };

  outputs = { self, nixpkgs, home-manager, astronvim }:
    let
      system = "x86_64-linux";
      overlays = [
        # Если в канале нет picom-pijulius — используем обычный picom
        (final: prev: {
          picom-pijulius = (prev.picom-pijulius or prev.picom);
        })
      ];
      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in {
      nixosConfigurations.svetos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit astronvim; };
        modules = [
          ./hosts/svetos/configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit astronvim; };
            home-manager.users.statix = import ./home/statix/home.nix;
          }
        ];
      };
    };
}
