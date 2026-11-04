# nix-packages

Pacchetti Nix personali per `x86_64-linux`, esposti come flake.

## Uso da un flake NixOS

Aggiungi l'input al flake del tuo sistema:

```nix
inputs.nix-packages = {
  url = "github:rizzonicola/nix-packages";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Poi passa i pacchetti come `specialArgs` con nome `per`:

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

In `configuration.nix` puoi quindi scrivere `per.<nome>`:

```nix
{ pkgs, per, ... }: {
  environment.systemPackages = [
    per.nome-app
  ];
}
```

## Aggiungere un pacchetto

Crea `pkgs/<nome>/package.nix` (nome minuscolo, solo lettere, numeri e trattini), partendo da `templates/binary-tarball.nix` o `templates/appimage.nix`. Il pacchetto viene scoperto automaticamente: non serve modificare `flake.nix`. La procedura completa è descritta in [AGENTS.md](AGENTS.md).

La CI compila solo i pacchetti modificati; il workflow settimanale li aggiorna con nix-update e apre una pull request per pacchetto.
