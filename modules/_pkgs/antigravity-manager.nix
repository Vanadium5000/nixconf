{ pkgs, lib, ... }:

let
  pname = "antigravity-manager";
  version = "3.3.45";

  src = pkgs.fetchurl {
    url = "https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${version}/Antigravity.Tools_${version}_amd64.deb";
    hash = "sha256-jJAytsb/8OF7d7Ty9Dq5WV7bEWm0eO943vcdYfDO06E=";
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    pkgs.dpkg
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];

  buildInputs = with pkgs; [
    gtk3
    webkitgtk_4_1
    libsoup_3
    openssl_3
    libayatana-appindicator
    libpulseaudio
    alsa-lib
    curl
  ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r usr/* $out/

    # Ensure binary is executable and wrapped correctly
    chmod +x $out/bin/*

    # Fix desktop file Exec if needed
    if [ -f "$out/share/applications/antigravity-tools.desktop" ]; then
      substituteInPlace $out/share/applications/antigravity-tools.desktop \
        --replace 'Exec=antigravity-tools' 'Exec=${pname}'
    fi

    # Provide canonical binary name
    if [ ! -e "$out/bin/${pname}" ]; then
      ln -s $out/bin/antigravity_tools $out/bin/${pname}
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Antigravity Tools – Antigravity account manager";
    homepage = "https://github.com/lbjlaq/Antigravity-Manager";
    license = licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
