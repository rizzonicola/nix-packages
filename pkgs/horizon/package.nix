{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  libGL,
  libX11,
  libXcursor,
  libXi,
  libxkbcommon,
  udev,
  vulkan-loader,
  wayland,
}:

let
  runtimeLibs = [
    alsa-lib
    libGL
    libX11
    libXcursor
    libXi
    libxkbcommon
    stdenv.cc.cc.lib
    udev
    vulkan-loader
    wayland
  ];

  programs = [
    "horizon-client"
    "horizon-ctl"
    "horizon-prepare"
    "horizon-server"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "horizon";
  version = "2026.10.19";

  src = fetchurl {
    url = "https://github.com/horizon-rust/horizon/releases/download/v${finalAttrs.version}/horizon-linux-x86_64.tar.gz";
    hash = "sha256-1xZ6KoJKoJ6VmtDP/QL5RM791MiAuWApsY/Bgcad9hM=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt
    cp -a . $out/opt/horizon

    runHook postInstall
  '';

  postFixup = ''
    for program in ${lib.escapeShellArgs programs}; do
      makeWrapper $out/opt/horizon/$program $out/bin/$program \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
    done
  '';

  meta = {
    description = "Minecraft: Java Edition 26.3 rewritten from scratch in Rust";
    homepage = "https://github.com/horizon-rust/horizon";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "horizon-client";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
