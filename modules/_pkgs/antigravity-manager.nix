{ pkgs, lib, ... }:

let
  pname = "antigravity-manager";
  version = "3.3.7";

  unwrapped = pkgs.stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${version}/Antigravity.Tools-${version}-1.x86_64.rpm";
      hash = "sha256-dMkX0hpKpS8pIKUE34LflHOmWJgH2iI60lJTW+zH/pI=";
    };

    nativeBuildInputs = with pkgs; [
      rpm
      cpio
    ];

    unpackPhase = ''
      rpm2cpio $src | cpio -idmv
    '';

    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/share/applications
      mkdir -p $out/share/icons/hicolor/{32x32,128x128,256x256@2}/apps

      cp usr/bin/antigravity_tools $out/bin/
      cp usr/share/applications/*.desktop $out/share/applications/

      cp usr/share/icons/hicolor/32x32/apps/*.png $out/share/icons/hicolor/32x32/apps/
      cp usr/share/icons/hicolor/128x128/apps/*.png $out/share/icons/hicolor/128x128/apps/
      cp usr/share/icons/hicolor/256x256@2/apps/*.png $out/share/icons/hicolor/256x256@2/apps/
    '';

    meta = with lib; {
      description = "Antigravity Tools - Antigravity account manager";
      homepage = "https://github.com/lbjlaq/Antigravity-Manager";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "antigravity_tools";
    };
  };

in
pkgs.buildFHSEnv {
  name = pname;
  inherit version;

  targetPkgs =
    pkgs: with pkgs; [
      gtk3
      webkitgtk_4_1
      libsoup_3
      openssl_3
      glib
      gdk-pixbuf
      cairo
      pango
      atk
      libgcc
      bzip2
      zlib
      curl
      libayatana-appindicator
    ];

  multiPkgs =
    pkgs: with pkgs; [
      udev
      alsa-lib
      libpulseaudio
    ];

  runScript = "${unwrapped}/bin/antigravity_tools";

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    ln -s ${unwrapped}/share/icons $out/share/icons

    # Create desktop file
    cat > $out/share/applications/${pname}.desktop <<EOF
    [Desktop Entry]
    Name=Antigravity Tools
    Comment=Antigravity account manager
    Exec=$out/bin/${pname}
    Icon=antigravity_tools
    Terminal=false
    Type=Application
    Categories=Network;Utility;
    EOF
  '';

  meta = unwrapped.meta // {
    mainProgram = pname;
  };
}
