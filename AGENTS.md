# AI agent instructions: personal Nix packages repository

Flake with packages for x86_64-linux, on a NixOS machine. Each package lives in `pkgs/<name>/package.nix` and is discovered automatically: do not modify `flake.nix` to add one. CI builds only the packages that changed; a weekly workflow updates them with nix-update and opens one pull request per package.

You have full access to the computer, git and `gh`: complete the work autonomously. If a command is not installed, use it with `nix shell nixpkgs#<package>` or `nix run nixpkgs#<package>`.

## Task: add a package

The user provides the project's GitHub link and, usually, the Linux x86_64 archive link (.tar.gz, .tar.xz or .zip) from a release.

1. If the asset link is missing, find it with `gh release view --repo OWNER/REPO --json tagName,assets` and choose the generic Linux x86_64 archive. Discard other architectures, macOS, Windows, .deb and .rpm. Use an AppImage only if there is nothing else (`templates/appimage.nix`).
2. Download the archive to /tmp and inspect it without executing it: `tar tf` or `unzip -l`, `file`, `readelf -d` or `patchelf --print-needed`. Determine whether there is a single top-level directory, which is the main executable, which libraries are needed, whether there are .desktop files and icons, and whether it is Electron.
3. Compute the hash: `nix store prefetch-file --json <URL>` and use the `hash` field (sha256-... format).
4. Create the `add/<name>` branch. Copy `templates/binary-tarball.nix` to `pkgs/<name>/package.nix` and fill it in. The name is lowercase with hyphens ([a-z0-9-]). Write `version` as a literal string and use `${finalAttrs.version}` in the URL: nix-update needs it.
5. Run `git add pkgs/<name>` (flakes ignore untracked files), then `nix build .#<name> --print-build-logs`. If auto-patchelf reports missing libraries, add them to `buildInputs` by looking up the exact name in nixpkgs (`nix search nixpkgs`, `nix-locate`): do not guess.
6. Verify: `result/bin/<program> --version` (or `--help`) and `ldd`. For graphical apps check the .desktop file and icon.
7. Check for updates: `nix run nixpkgs#nix-update -- --flake <name>` must finish without errors (version already up to date). If it cannot find the upstream version, check `--help` (for example `--url` with the GitHub link). If the repository publishes several release series (nightlies, launcher, etc.), add `pkgs/<name>/nix-update-args` with one extra nix-update argument per line; the weekly workflow reads it automatically.
8. Run `nix flake check --no-build`.
9. Commit (`<name>: init <version>`), push the branch and run `gh pr create`. Follow CI with `gh pr checks --watch`: it must build only `<name>`. If it fails, read the logs (`gh run view --log-failed`), fix, push and repeat. When green, merge with `gh pr merge --squash --delete-branch`, then `git checkout main && git pull` and check that CI on `main` is green too.
10. Reply with: package added and version, libraries added and why, what you verified and what you did not, pull request URL and the configuration.nix line (`per.<name>` inside `environment.systemPackages`).

## Task: update or repair a package

The user gives the package name and, usually, the symptom: failing build in CI, nix-update error, app that does not start, missing library, or a specific version to install.

1. Reproduce the problem: `nix build .#<name> --print-build-logs`. If it comes from CI, look at `gh run list --limit 5` and `gh run view <id> --log-failed`. If there is an open automatic pull request for that package (branch `auto/update-<name>`, see `gh pr list`), work directly on that branch with `gh pr checkout` instead of opening another one.
2. To update: `nix run nixpkgs#nix-update -- --flake <name>` (or `--version <X.Y.Z>` for a specific version). If nix-update does not work, update `version` and `hash` manually (`nix store prefetch-file --json <URL>`).
3. If the asset changed (file name, top-level directory, archive structure, executable moved), download and inspect it again as in step 2 of "add a package", then fix `url`, `sourceRoot` and `installPhase`.
4. Typical causes: wrong hash; missing library reported by auto-patchelf (add it to `buildInputs`); library renamed or moved in nixpkgs (search for it with `nix search nixpkgs`); new runtime dependency (add it to the wrapper with `makeWrapper --prefix PATH` or `--prefix LD_LIBRARY_PATH`); asset renamed or removed upstream; major version jump with a different structure.
5. After the fix, repeat the checks: build, `result/bin/<program> --version`, `nix run nixpkgs#nix-update -- --flake <name>` without errors, `nix flake check --no-build`.
6. Create the `fix/<name>` branch (except for the automatic pull request case in step 1), commit (`<name>: <what you fixed>`), push, open a pull request, run `gh pr checks --watch` and merge when green, as in step 9 of "add a package".
7. If the problem is upstream and cannot be fixed (asset removed, project abandoned, license changed), keep the current version, explain the situation and do not invent solutions.
8. Reply with: cause of the problem, fix applied, checks performed, pull request URL.

## Rules

- x86_64-linux only. Do not invent URLs, hashes or licenses: if the license is unclear, use `lib.licenses.unfree` and report it.
- No downloads during the build: the network is available only for `fetchurl` and `fetchFromGitHub`.
- `meta` must always be complete: description, homepage, license, platforms, mainProgram, sourceProvenance.
- If the release contains only sources, use the language builder with `fetchFromGitHub`: `buildGoModule` (vendorHash), `rustPlatform.buildRustPackage` (cargoHash), `buildNpmPackage` (npmDepsHash), `python3Packages.buildPythonApplication`. For vendoring hashes start from `lib.fakeHash` and read the correct one from the error.
- Electron apps: often need `wrapGAppsHook3` and libraries such as gtk3, nss, alsa-lib, libxkbcommon.
- Archive with many files: copy everything to `$out/opt/<name>` and create the command with `makeWrapper`.
- To add, update or repair packages you may commit, push, open pull requests and merge autonomously. Ask me first only if you need to modify `flake.nix`, the workflows, or packages other than the one specified.
- If essential information is missing, ask instead of guessing.
