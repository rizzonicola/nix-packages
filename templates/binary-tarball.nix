{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip, # only if the archive is a .zip, otherwise remove it
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "example-app";
  version = "1.2.3";

  src = fetchurl {
    url = "https://github.com/OWNER/REPO/releases/download/v${finalAttrs.version}/example-app-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    unzip
  ];

  # libraries reported as missing by auto-patchelf go here
  buildInputs = [ stdenv.cc.cc.lib ];

  # if the archive does NOT have a single top-level directory, uncomment:
  # sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 example-app $out/bin/example-app
    runHook postInstall
  '';

  meta = {
    description = "Short description";
    homepage = "https://github.com/OWNER/REPO";
    license = lib.licenses.mit; # lib.licenses.unfree if unclear
    platforms = [ "x86_64-linux" ];
    mainProgram = "example-app";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
