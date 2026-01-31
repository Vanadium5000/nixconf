# Microsoft Aptos Font Family - Microsoft's new default font replacing Calibri
# Includes: Aptos, Aptos Display, Aptos Mono, Aptos Narrow, Aptos Serif
{
  lib,
  stdenvNoCC,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "aptos-fonts";
  version = "2024.05.29";

  src = ./assets/Microsoft-Aptos-Fonts-Family.zip;

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip $src -d .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/fonts/truetype/aptos *.ttf
    runHook postInstall
  '';

  meta = {
    description = "Microsoft Aptos font family - successor to Calibri";
    homepage = "https://learn.microsoft.com/en-us/typography/font-list/aptos";
    license = lib.licenses.unfree; # Microsoft proprietary
    platforms = lib.platforms.all;
  };
}
