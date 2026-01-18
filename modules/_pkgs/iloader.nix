{
  lib,
  appimageTools,
  fetchurl,
  ...
}:
appimageTools.wrapType2 {
  pname = "iloader";
  version = "1.1.6";

  src = fetchurl {
    url = "https://github.com/nab138/iloader/releases/download/v1.1.6/iloader-linux-amd64.AppImage";
    sha256 = "sha256-L1fFwFjdIrrhviBlwORhSDXsNYgrT1NcVKAKlss6h4o=";
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
