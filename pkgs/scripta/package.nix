{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  gtk3,
  libGL,
  libepoxy,
  libsecret,
  fontconfig,
  zlib,
}:

let
  runtimeLibs = [
    gtk3
    libGL
    libepoxy
    libsecret
    fontconfig
    zlib
    stdenv.cc.cc.lib
  ];

  desktopItem = makeDesktopItem {
    name = "io.github.scripta.Scripta";
    desktopName = "Scripta";
    genericName = "Note-taking App";
    comment = "Minimal, Markdown-first note-taking application";
    exec = "scripta %U";
    icon = "io.github.scripta.Scripta";
    terminal = false;
    categories = [
      "Office"
      "TextEditor"
    ];
    mimeTypes = [
      "text/markdown"
      "text/x-markdown"
      "text/plain"
      "inode/directory"
    ];
    startupWMClass = "scripta";
  };

  # The release archive does not contain the desktop icon. Pin it to the
  # v1.1.3 commit so that nix-update can bump the application without having
  # to refresh an extra hash.
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/rizzonicola/Scripta/9a7e81e12be086262df70b69211ff7f8fd410f65/linux/packaging/icons/512x512.png";
    hash = "sha256-qRLIXKL/spzmEAf+XbKL8rLB8WhwnaB4Hho/8cjcOhU=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "scripta";
  version = "1.1.3";

  src = fetchurl {
    url = "https://github.com/rizzonicola/Scripta/releases/download/v${finalAttrs.version}/Scripta-linux-x64.tar.gz";
    hash = "sha256-jOT0d0rQI22lPleyYb2D/LDSS48fgDxapnO0ivNAAq4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/scripta
    cp -a . $out/opt/scripta/
    # The upstream archive stores the executable and the shared libraries
    # without the executable bit.
    chmod +x $out/opt/scripta/scripta $out/opt/scripta/lib/*.so

    # The Dart sqlite3 package loads "libsqlite3.so" by name at runtime, so the
    # bundled library directory must be on the loader path as well.
    makeWrapper $out/opt/scripta/scripta $out/bin/scripta \
      --prefix LD_LIBRARY_PATH : $out/opt/scripta/lib \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}

    install -Dm644 ${desktopItem}/share/applications/io.github.scripta.Scripta.desktop \
      $out/share/applications/io.github.scripta.Scripta.desktop
    install -Dm644 ${icon} \
      $out/share/icons/hicolor/512x512/apps/io.github.scripta.Scripta.png

    runHook postInstall
  '';

  meta = {
    description = "Minimal, Markdown-first note-taking application";
    homepage = "https://github.com/rizzonicola/Scripta";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "scripta";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
