# Istruzioni per agenti AI: repository di pacchetti Nix personali

Flake con pacchetti per x86_64-linux, su una macchina NixOS. Ogni pacchetto sta in `pkgs/<nome>/package.nix` e viene scoperto automaticamente: non modificare `flake.nix` per aggiungerne uno. La CI compila solo i pacchetti modificati; un workflow settimanale li aggiorna con nix-update e apre una pull request per pacchetto.

Hai accesso completo al computer, a git e a `gh`: porta a termine il lavoro in autonomia. Se un comando non è installato, usalo con `nix shell nixpkgs#<pacchetto>` o `nix run nixpkgs#<pacchetto>`.

## Compito: aggiungere un pacchetto

L'utente fornisce il link GitHub del progetto e, di solito, il link dell'archivio Linux x86_64 (.tar.gz, .tar.xz o .zip) di una release.

1. Se manca il link dell'asset, trovalo con `gh release view --repo OWNER/REPO --json tagName,assets` e scegli l'archivio Linux x86_64 generico. Scarta altre architetture, macOS, Windows, .deb e .rpm. Usa un AppImage solo se non c'è altro (`templates/appimage.nix`).
2. Scarica l'archivio in /tmp e ispezionalo senza eseguirlo: `tar tf` o `unzip -l`, `file`, `readelf -d` o `patchelf --print-needed`. Stabilisci se c'è una cartella radice unica, qual è l'eseguibile principale, quali librerie servono, se ci sono .desktop e icone, se è Electron.
3. Calcola l'hash: `nix store prefetch-file --json <URL>` e usa il campo `hash` (formato sha256-...).
4. Crea il branch `add/<nome>`. Copia `templates/binary-tarball.nix` in `pkgs/<nome>/package.nix` e compilalo. Il nome è minuscolo con trattini ([a-z0-9-]). Scrivi `version` come stringa letterale e usa `${finalAttrs.version}` nell'URL: serve a nix-update.
5. Esegui `git add pkgs/<nome>` (i flake ignorano i file non tracciati), poi `nix build .#<nome> --print-build-logs`. Se auto-patchelf segnala librerie mancanti, aggiungile a `buildInputs` cercando il nome esatto in nixpkgs (`nix search nixpkgs`, `nix-locate`): non indovinare.
6. Verifica: `result/bin/<programma> --version` (o `--help`) e `ldd`. Per le app grafiche controlla .desktop e icona.
7. Controlla gli aggiornamenti: `nix run nixpkgs#nix-update -- --flake <nome>` deve finire senza errori (versione già aggiornata). Se non trova la versione upstream, guarda `--help` (per esempio `--url` con il link GitHub).
8. Esegui `nix flake check --no-build`.
9. Fai commit (`<nome>: init <versione>`), push del branch e `gh pr create`. Segui la CI con `gh pr checks --watch`: deve compilare solo `<nome>`. Se fallisce, leggi i log (`gh run view --log-failed`), correggi, fai push e ripeti. Quando è verde fai merge con `gh pr merge --squash --delete-branch`, poi `git checkout main && git pull` e controlla che anche la CI su `main` sia verde.
10. Rispondi con: pacchetto aggiunto e versione, librerie aggiunte e perché, cosa hai verificato e cosa no, URL della pull request e la riga per configuration.nix (`per.<nome>` dentro `environment.systemPackages`).

## Compito: aggiornare o riparare un pacchetto

L'utente indica il nome del pacchetto e, di solito, il sintomo: build che fallisce in CI, errore di nix-update, app che non parte, libreria mancante, oppure una versione precisa da installare.

1. Riproduci il problema: `nix build .#<nome> --print-build-logs`. Se arriva dalla CI guarda `gh run list --limit 5` e `gh run view <id> --log-failed`. Se c'è una pull request automatica aperta per quel pacchetto (branch `auto/update-<nome>`, vedi `gh pr list`), lavora direttamente su quel branch con `gh pr checkout` invece di aprirne un'altra.
2. Per aggiornare: `nix run nixpkgs#nix-update -- --flake <nome>` (oppure `--version <X.Y.Z>` per una versione precisa). Se nix-update non funziona, aggiorna a mano `version` e `hash` (`nix store prefetch-file --json <URL>`).
3. Se l'asset è cambiato (nome del file, cartella radice, struttura dell'archivio, eseguibile spostato), riscaricalo e ispezionalo di nuovo come nel passo 2 di "aggiungere un pacchetto", poi correggi `url`, `sourceRoot` e `installPhase`.
4. Cause tipiche: hash sbagliato; libreria mancante segnalata da auto-patchelf (aggiungila a `buildInputs`); libreria rinominata o spostata in nixpkgs (cercala con `nix search nixpkgs`); nuova dipendenza a runtime (aggiungila al wrapper con `makeWrapper --prefix PATH` o `--prefix LD_LIBRARY_PATH`); asset rinominato o rimosso dall'upstream; salto di versione major con struttura diversa.
5. Dopo la correzione ripeti le verifiche: build, `result/bin/<programma> --version`, `nix run nixpkgs#nix-update -- --flake <nome>` senza errori, `nix flake check --no-build`.
6. Crea il branch `fix/<nome>` (salvo il caso della pull request automatica del passo 1), fai commit (`<nome>: <cosa hai corretto>`), push, pull request, `gh pr checks --watch` e merge quando è verde, come nel passo 9 di "aggiungere un pacchetto".
7. Se il problema è upstream e non risolvibile (asset rimosso, progetto abbandonato, licenza cambiata), lascia la versione attuale, spiega la situazione e non inventare soluzioni.
8. Rispondi con: causa del problema, correzione fatta, verifiche eseguite, URL della pull request.

## Regole

- Solo x86_64-linux. Non inventare URL, hash o licenze: se la licenza non è chiara usa `lib.licenses.unfree` e segnalalo.
- Nessun download durante il build: la rete è disponibile solo per `fetchurl` e `fetchFromGitHub`.
- `meta` sempre completo: description, homepage, license, platforms, mainProgram, sourceProvenance.
- Se la release contiene solo sorgenti, usa il builder del linguaggio con `fetchFromGitHub`: `buildGoModule` (vendorHash), `rustPlatform.buildRustPackage` (cargoHash), `buildNpmPackage` (npmDepsHash), `python3Packages.buildPythonApplication`. Per gli hash di vendoring parti da `lib.fakeHash` e leggi quello corretto dall'errore.
- App Electron: spesso servono `wrapGAppsHook3` e librerie come gtk3, nss, alsa-lib, libxkbcommon.
- Archivio con molti file: copia tutto in `$out/opt/<nome>` e crea il comando con `makeWrapper`.
- Per aggiungere, aggiornare o riparare pacchetti puoi fare commit, push, pull request e merge in autonomia. Chiedimi prima solo se devi modificare `flake.nix`, i workflow o pacchetti diversi da quello indicato.
- Se mancano informazioni essenziali, chiedi invece di tirare a indovinare.
