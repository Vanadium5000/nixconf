{ pkgs, ... }:

let
  pname = "dogecoin";
  version = "1.14.9";
in
pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = pkgs.fetchurl {
    url = "https://github.com/dogecoin/dogecoin/releases/download/v${version}/dogecoin-${version}-x86_64-linux-gnu.tar.gz";
    hash = "sha256-TyJxF7QRp8mGIslwmG4nvPw/VHpyvvZefZ6CmJF11Pg=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp bin/dogecoin-cli $out/bin/
    cp bin/dogecoind $out/bin/
    cp bin/dogecoin-tx $out/bin/

    runHook postInstall
  '';

  meta = {
    description = "Dogecoin Core - CLI tools for the Dogecoin cryptocurrency";
    homepage = "https://github.com/dogecoin/dogecoin";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "dogecoin-cli";
  };
}
