{
  lib,
  appimageTools,
  fetchurl,
  ...
}:
let
  version = "1.1.6";
in
appimageTools.wrapType2 {
  pname = "iloader";
  inherit version;

  src = fetchurl {
    url = "https://github.com/nab138/iloader/releases/download/v${version}/iloader-linux-amd64.AppImage";
    hash = "sha256-L1fFwFjdIrrhviBlwORhSDXsNYgrT1NcVKAKlss6h4o=";
  };

  extraPkgs =
    pkgs: with pkgs; [
      libusbmuxd
      libimobiledevice
    ];

  meta = {
    description = "User friendly sideloader";
    homepage = "https://github.com/nab138/iloader";
    downloadPage = "https://github.com/nab138/iloader/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
