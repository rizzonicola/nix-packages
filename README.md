# nix-packages

Personal Nix packages for `x86_64-linux`, exposed as a flake.

## Usage from a NixOS flake

Add the input to your system flake:

```nix
inputs.nix-packages = {
  url = "github:rizzonicola/nix-packages";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then pass the packages as `specialArgs` under the name `per`:

```nix
outputs = { self, nixpkgs, nix-packages, ... }: {
  nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      per = nix-packages.packages.x86_64-linux;
    };
    modules = [ ./configuration.nix ];
  };
};
```

In `configuration.nix` you can then write `per.<name>`:

```nix
{ pkgs, per, ... }: {
  environment.systemPackages = [
    per.some-app
  ];
}
```

## Adding a package

Create `pkgs/<name>/package.nix` (lowercase name, letters, numbers and hyphens only), starting from `templates/binary-tarball.nix` or `templates/appimage.nix`. The package is discovered automatically: there is no need to edit `flake.nix`. If the project publishes several release series (nightlies, launcher, etc.), add `pkgs/<name>/nix-update-args` with one extra nix-update argument per line. Graphical packages must install a `.desktop` entry and icons; if upstream ships a hidden client plus a launcher, package the launcher as the user-facing app. The full procedure is described in [AGENTS.md](AGENTS.md).

CI builds only the packages that changed; the weekly workflow first checks the upstream releases, then runs nix-update only for the packages that are actually behind and opens one pull request per package.
