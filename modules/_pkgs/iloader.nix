{
  lib,
  appimageTools,
  pkgs,
  ...
}:
let
  sources = pkgs.callPackage ./_sources/generated.nix { };
  source = sources.iloader;
in
appimageTools.wrapType2 {
  inherit (source) pname version src;

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
