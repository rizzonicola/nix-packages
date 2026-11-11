{
  lib,
  stdenvNoCC,
  fetchurl,
  buildFHSEnv,
  makeDesktopItem,
  writeShellScript,
}:

stdenvNoCC.mkDerivation (finalAttrs:
  let
    # The launcher downloads game builds and Mojang's Java runtimes and runs
    # them. Those are ordinary Linux binaries, so they need an FHS environment
    # with /lib64/ld-linux-x86-64.so.2 and the usual graphics/audio libraries.
    unwrapped = stdenvNoCC.mkDerivation {
      pname = "${finalAttrs.pname}-unwrapped";
      version = finalAttrs.version;

      src = finalAttrs.src;

      sourceRoot = ".";

      dontConfigure = true;
      dontBuild = true;
      dontStrip = true;
      dontPatchELF = true;

      installPhase = ''
        runHook preInstall
        install -Dm755 horizon-launcher $out/bin/horizon-launcher
        runHook postInstall
      '';
    };

    fhs = buildFHSEnv {
      pname = "${finalAttrs.pname}-fhs";
      version = finalAttrs.version;
      executableName = finalAttrs.pname;

      targetPkgs = pkgs: with pkgs; [
        # Launcher and game windows (winit + wgpu)
        vulkan-loader
        libglvnd
        wayland
        libxkbcommon
        libx11
        libxcb
        libxcursor
        libxext
        libxi
        libxrandr
        libxrender
        libxxf86vm

        # Game input and sound. The host's /etc/alsa config routes ALSA to
        # PipeWire or PulseAudio through its own plugins.
        udev
        alsa-lib

        # Fonts, D-Bus (keyring), opening links, process checks
        fontconfig
        freetype
        dbus
        xdg-utils
        procps

        # Mojang's Java runtime, which prepares the game's resources
        zlib
        libxtst

        # The launcher's optional GameMode toggle
        gamemode

        # Building native mods: before downloading anything the launcher
        # checks for a C compiler, pkg-config and the development files of
        # ALSA and libudev, then cargo links against the libraries the game
        # uses. Runtime outputs carry neither headers, .pc files nor the
        # unversioned .so symlinks, so their dev outputs are needed too.
        stdenv.cc
        pkg-config
        clang
        llvmPackages.libclang.lib
        mold
        glibc.dev
        alsa-lib.dev
        udev.dev
        libxkbcommon.dev
        wayland.dev
        wayland-scanner
        vulkan-loader.dev
        fontconfig.dev
        freetype.dev
        openssl
        openssl.dev
        xorgproto
        libx11.dev
        libxcb.dev
        libxcursor.dev
        libxfixes
        libxfixes.dev
        libxrandr.dev
        libxrender.dev
        libxext.dev
        libxi.dev
      ];

      runScript = "${unwrapped}/bin/horizon-launcher";

      # Nix updates the launcher, so it must not replace itself in the
      # read-only store. Menu entries it writes for instances call the wrapper
      # on PATH, which survives updates and garbage collection, rather than a
      # store path.
      profile = ''
        export HORIZON_LAUNCHER_NO_SELF_UPDATE=1
        export HORIZON_LAUNCHER_DESKTOP_EXEC="''${HORIZON_LAUNCHER_DESKTOP_EXEC:-${finalAttrs.pname}}"

        # Native mod builds use bindgen, which finds libclang through this.
        export LIBCLANG_PATH=/usr/lib

        # The X11 protocol descriptions (xorgproto) live in share/pkgconfig;
        # the FHS profile only points pkg-config at lib/pkgconfig.
        export PKG_CONFIG_PATH="/usr/share/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
      '';
    };

    # Upstream now ships only Nightly builds, and its default is to install the
    # newest one automatically. This repository packages stable releases, so
    # the first run turns automatic installs off; the user can still install
    # vX.Y.Z by hand or turn the setting back on.
    launcher = writeShellScript "${finalAttrs.pname}-wrapper" ''
      set -euo pipefail

      case "''${1:-}" in
        -h|--help|-V|--version|help|completions)
          exec ${fhs}/bin/${finalAttrs.pname} "$@"
          ;;
      esac

      data_home="''${XDG_DATA_HOME:-}"
      case "$data_home" in
        /*) ;;
        *) data_home="''$HOME/.local/share" ;;
      esac
      data_dir="''${HORIZON_LAUNCHER_HOME:-$data_home/horizon-launcher}"

      if [ ! -e "$data_dir/settings.json" ] \
        && [ "''${HORIZON_LAUNCHER_UPSTREAM_DEFAULTS:-0}" != "1" ]; then
        ${fhs}/bin/${finalAttrs.pname} settings install-new-versions off >/dev/null 2>&1 || true
      fi

      exec ${fhs}/bin/${finalAttrs.pname} "$@"
    '';

    desktopItem = makeDesktopItem {
      name = finalAttrs.pname;
      desktopName = "Horizon";
      genericName = "Game launcher";
      comment = "Install, prepare and play Horizon, Minecraft: Java Edition rewritten in Rust";
      exec = finalAttrs.pname;
      icon = "horizon";
      categories = [ "Game" ];
      startupWMClass = "horizon-launcher";
    };
  in
  {
    pname = "horizon-launcher";
    version = "0.2.59";

    src = fetchurl {
      url = "https://github.com/horizon-rust/horizon/releases/download/launcher@${finalAttrs.version}/horizon-launcher-linux-x86_64.tar.gz";
      hash = "sha256-2I+Qn9c+9tDaTmqCxEcke8NznSkaqbbDnmkoOe1h8NQ=";
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 ${launcher} $out/bin/${finalAttrs.pname}

      install -Dm444 ${desktopItem}/share/applications/${finalAttrs.pname}.desktop \
        $out/share/applications/${finalAttrs.pname}.desktop
      install -Dm444 ${./assets/horizon.svg} \
        $out/share/icons/hicolor/scalable/apps/horizon.svg
      install -Dm444 ${./assets/horizon-256.png} \
        $out/share/icons/hicolor/256x256/apps/horizon.png

      runHook postInstall
    '';

    passthru = {
      inherit fhs unwrapped;
    };

    meta = {
      description = "Launcher for Horizon, Minecraft: Java Edition rewritten in Rust";
      longDescription = ''
        Installs, prepares, updates and plays Horizon, an unofficial rewrite of
        Minecraft: Java Edition in Rust. Horizon prepares its resources from your
        own copy of Minecraft: Java Edition.

        Upstream now publishes only Nightly builds as automatic updates. This
        package turns automatic installs off on first run so the launcher stays
        on a stable vX.Y.Z release, which can still be installed by hand. Set
        HORIZON_LAUNCHER_UPSTREAM_DEFAULTS=1 to keep upstream's default.
      '';
      homepage = "https://playhorizon.dev";
      changelog = "https://github.com/horizon-rust/horizon/releases/tag/launcher@${finalAttrs.version}";
      license = lib.licenses.mit;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "horizon-launcher";
    };
  })
