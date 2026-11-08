{
  lib,
  python3Packages,
  fetchurl,
  wrapGAppsHook3,
  gobject-introspection,
  gtk3,
  libappindicator-gtk3,
  makeDesktopItem,
  xclip,
  wl-clipboard,
  xdg-utils,
  libnotify,
}:

let
  desktopItem = makeDesktopItem {
    name = "clipcascade";
    desktopName = "ClipCascade";
    genericName = "Clipboard Synchronizer";
    comment = "Sync the clipboard across devices with end-to-end encryption";
    exec = "clipcascade";
    icon = "clipcascade";
    terminal = false;
    categories = [ "Utility" ];
  };

  # Used through subprocess at runtime. notify-send is picked by plyer when
  # the desktop portal is not available.
  runtimeDeps = [
    xclip
    wl-clipboard
    xdg-utils
    libnotify
  ];
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "clipcascade";
  version = "3.4.1";
  pyproject = true;

  # The release archive is the only source tree that carries the version
  # stamped into core/constants.py by the upstream release workflow; the git
  # tag still reports 3.4.0. Its GitHub release download also lets
  # nix-update track new versions.
  src = fetchurl {
    url = "https://github.com/Sathvik-Rao/ClipCascade/releases/download/v${finalAttrs.version}/ClipCascade_Linux.tar.xz";
    hash = "sha256-0gzpJbDuy3bzYiS8EhrEVyrs1IR/ddHPyiNVuBg7wl8=";
  };

  sourceRoot = "ClipCascade";

  patches = [ ./xdg-config-dir.patch ];

  build-system = [ python3Packages.setuptools ];

  # Upstream pins exact versions; nixpkgs carries newer compatible releases
  # (aiortc 1.15, PyAV 19, Pillow 12.3, ...).
  dontCheckRuntimeDeps = true;

  dependencies = with python3Packages; [
    aiortc
    beautifulsoup4
    pillow
    plyer
    pycryptodome
    pyfiglet
    pygobject3
    pystray
    prompt-toolkit
    requests
    tkinter
    websocket-client
    xxhash
  ];

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  # GTK 3 and AppIndicator are imported through PyGObject for the tray icon,
  # the login window and the X11 clipboard monitor.
  buildInputs = [
    gtk3
    libappindicator-gtk3
  ];

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    );
  '';

  postInstall = ''
    install -Dm644 ${desktopItem}/share/applications/clipcascade.desktop \
      $out/share/applications/clipcascade.desktop
    # Upstream logo (GPL-3.0), the archive does not ship it.
    install -Dm644 ${./clipcascade.svg} \
      $out/share/icons/hicolor/scalable/apps/clipcascade.svg
  '';

  # pystray selects and imports its backend at import time, which needs a
  # display; in the build sandbox it falls back to the Xlib backend and fails.
  # Check the non-GUI modules here and exercise the entry point under
  # xvfb-run instead.
  pythonImportsCheck = [
    "core.constants"
    "core.config"
    "utils.cipher_manager"
    "utils.request_manager"
  ];

  meta = {
    description = "Clipboard synchronization utility with end-to-end encryption";
    longDescription = ''
      ClipCascade keeps the clipboard in sync across devices. It runs as a GTK
      tray application on X11/XWayland and as a terminal application on native
      Wayland, and uses xclip or wl-clipboard for the local clipboard.
    '';
    homepage = "https://clipcascade.sathvik.dev/";
    changelog = "https://github.com/Sathvik-Rao/ClipCascade/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "clipcascade";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
