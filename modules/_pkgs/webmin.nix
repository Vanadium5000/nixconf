{
  fetchurl,
  lib,
  perl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  pname = "webmin";
  version = "2.641";

  src = fetchurl {
    url = "https://github.com/webmin/webmin/releases/download/${version}/webmin-${version}-minimal.tar.gz";
    hash = "sha256-GnJE+tAsoWUi60IrO4a543JTQXiOY/Rkifsgh6ZKwN4=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/webmin $out/bin
    cp -R . $out/libexec/webmin/
    patchShebangs $out/libexec/webmin

    substituteInPlace $out/libexec/webmin/miniserv.pl \
      --replace-fail '#!/usr/local/bin/perl' '#!${perl}/bin/perl'

    ln -s $out/libexec/webmin/miniserv.pl $out/bin/webmin-miniserv

    runHook postInstall
  '';

  meta = {
    description = "Web-based system administration interface for Unix-like systems";
    homepage = "https://webmin.com/";
    license = lib.licenses.bsd3;
    mainProgram = "webmin-miniserv";
    platforms = lib.platforms.linux;
  };
}
