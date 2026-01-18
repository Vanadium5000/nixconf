{ pkgs, lib, ... }:

let
  pname = "antigravity-manager";
  version = "3.3.43";

  src = pkgs.fetchurl {
    url = "https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${version}/Antigravity.Tools_${version}_amd64.AppImage";
    hash = "sha256-ZWnoww9zM5weJfAAowJldWkl66vLX564PFXSHEvVUFQ=";
  };

  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs =
    pkgs: with pkgs; [
      gtk3
      webkitgtk_4_1
      libsoup_3
      openssl_3
      libayatana-appindicator
      libpulseaudio
      alsa-lib
      curl
    ];

  extraInstallCommands = ''
    install -m 444 -D "${appimageContents}/Antigravity Tools.desktop" $out/share/applications/${pname}.desktop
    install -m 444 -D "${appimageContents}/Antigravity Tools.png" \
      $out/share/icons/hicolor/512x512/apps/antigravity_tools.png

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=antigravity_tools' 'Exec=${pname}'
  '';

  meta = with lib; {
    description = "Antigravity Tools - Antigravity account manager";
    homepage = "https://github.com/lbjlaq/Antigravity-Manager";
    license = licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
