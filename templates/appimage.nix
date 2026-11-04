{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "nome-app";
  version = "1.2.3";
  src = fetchurl {
    url = "https://github.com/OWNER/REPO/releases/download/v${version}/nome-app-${version}.AppImage";
    hash = lib.fakeHash;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;
  meta = {
    description = "Descrizione breve";
    homepage = "https://github.com/OWNER/REPO";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nome-app";
  };
}
