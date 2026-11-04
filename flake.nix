{
  description = "My personal Nix packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      mkPackages =
        callPackage:
        lib.filesystem.packagesFromDirectoryRecursive {
          inherit callPackage;
          directory = ./pkgs;
        };
    in
    {
      packages.${system} = mkPackages pkgs.callPackage;
      overlays.default = final: _prev: mkPackages final.callPackage;
    };
}
