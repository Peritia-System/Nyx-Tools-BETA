{
  description = "EXAMPLE-flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nyx.url = "github:Peritia-System/Nyx-Tools";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    nyx,
    ...
  }: {

    nixosModules.nixos95 = import ./nixos95;

    nixosConfigurations = {
      default = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs self;
          host = "default";
        };
        modules = [
          ./Configurations/Hosts/Default/configuration.nix
          # No need to include nyx here
        ];
      };
    };
  };
}
{ config, pkgs, host, lib, inputs, userconf, ... }:

let
  username = "YOUR_USER";
  nixDirectory = "/home/${username}/NixOS";
in {
  ################################################################
  # Module Imports
  ################################################################

  imports = [
    # Home Manager integration
    inputs.home-manager.nixosModules.home-manager
  ];

  ################################################################
  # Home Manager Configuration
  ################################################################

home-manager = {
  useGlobalPkgs = true;
  useUserPackages = true;
  backupFileExtension = "delme-HMbackup";
  users.${username} = import ./home.nix;

  extraSpecialArgs = {
    inherit inputs nixDirectory username;
  };
};
  ################################################################
  # System Version
  ################################################################

  system.stateVersion = "25.05";

  # ... Add more
}
{ config, nixDirectory, username, pkgs, inputs, ... }:

{

  ################################################################
  # Module Imports
  ################################################################

  imports = [
    # Other Home Manager Modules
    # ......
    inputs.nyx.homeManagerModules.default
  ];

  ################################################################
  # Nyx Tools Configuration
  ################################################################

  nyx.nyx-rebuild = {
    enable = true;
    inherit username nixDirectory;
    editor = "nvim";
    formatter = "alejandra";
    enableAlias = false;
    autoPushLog = false;
    autoPushNixDir = false;
    startEditor = false;
  };
  
  nyx.nyx-cleanup = {
    enable = true;
    inherit username nixDirectory;
    autoPush = false;
    keepGenerations = 5;
    enableAlias = false;
  };
  
  nyx.nyx-tool = {
    enable = true;
    inherit nixDirectory;
  };


  ################################################################
  # Basic Home Manager Setup
  ################################################################

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.05";
}
