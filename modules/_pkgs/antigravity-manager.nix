{ pkgs, ... }:

let
  pname = "antigravity-manager";
  version = "3.3.50";

  unwrapped = pkgs.stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${version}/Antigravity.Tools-${version}-1.x86_64.rpm";
      hash = "sha256-nX93JKvPFVFEnZ3lX+oTm+aAJ0fHLGNOG0SBpgzmHFw=";
    };

    nativeBuildInputs = with pkgs; [
      rpm
      cpio
    ];

    unpackPhase = ''
      rpm2cpio $src | cpio -idmv
    '';

    installPhase = ''
      mkdir -p $out/bin \
               $out/share/applications \
               $out/share/icons/hicolor/{32x32,128x128,256x256@2}/apps

      cp usr/bin/antigravity_tools $out/bin/antigravity_tools

      # Copy desktop file(s) and icons if they exist
      cp usr/share/applications/*.desktop $out/share/applications/ || true
      cp usr/share/icons/hicolor/32x32/apps/*.png   $out/share/icons/hicolor/32x32/apps/   || true
      cp usr/share/icons/hicolor/128x128/apps/*.png $out/share/icons/hicolor/128x128/apps/ || true
      cp usr/share/icons/hicolor/256x256@2/apps/*.png $out/share/icons/hicolor/256x256@2/apps/ || true
    '';

    meta = # with lib;
      {
        description = "Antigravity Manager - Antigravity account manager";
        homepage = "https://github.com/lbjlaq/Antigravity-Manager";
        # license = licenses.unfree;
        platforms = [ "x86_64-linux" ];
      };
  };
in
(pkgs.buildFHSEnv {
  name = pname;
  inherit pname;
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
    mkdir -p $out/share/applications $out/share/icons/hicolor

    # Copy icons from unwrapped derivation
    cp -r ${unwrapped}/share/icons/hicolor/* $out/share/icons/hicolor/ || true

    # Create a clean desktop entry pointing to the FHS wrapper
    cat > $out/share/applications/antigravity-manager.desktop <<EOF
    [Desktop Entry]
    Name=Antigravity Manager
    Comment=Antigravity account manager
    Exec=antigravity-manager %U
    Icon=antigravity_tools
    Terminal=false
    Type=Application
    Categories=Network;Utility;
    EOF
  '';

  meta = # with lib;
    {
      description = "Antigravity Manager - Antigravity account manager";
      homepage = "https://github.com/lbjlaq/Antigravity-Manager";
      # license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit unwrapped;
    };
  })
