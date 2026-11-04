{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip, # solo se l'archivio è uno .zip, altrimenti rimuovilo
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nome-app";
  version = "1.2.3";

  src = fetchurl {
    url = "https://github.com/OWNER/REPO/releases/download/v${finalAttrs.version}/nome-app-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    unzip
  ];

  # librerie che auto-patchelf segnala come mancanti vanno aggiunte qui
  buildInputs = [ stdenv.cc.cc.lib ];

  # se l'archivio NON ha una cartella radice unica, decommenta:
  # sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 nome-app $out/bin/nome-app
    runHook postInstall
  '';

  meta = {
    description = "Descrizione breve";
    homepage = "https://github.com/OWNER/REPO";
    license = lib.licenses.mit; # lib.licenses.unfree se non è chiara
    platforms = [ "x86_64-linux" ];
    mainProgram = "nome-app";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
