# Waydroid Total Spoof - Device identity spoofing toolkit for Waydroid
# Spoofs device model, manufacturer, build fingerprint, and Android/GSF IDs
# to make Waydroid appear as a real physical device (bypass emulator detection)
# https://github.com/lil-xhris/Waydroid-total-spoof
{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  coreutils,
  gnused,
  gnugrep,
  gawk,
  openssl,
}:

stdenv.mkDerivation {
  pname = "waydroid-total-spoof";
  version = "0-unstable-2025-08-18"; # No releases/tags - tracks main branch

  src = fetchFromGitHub {
    owner = "lil-xhris";
    repo = "Waydroid-total-spoof";
    rev = "0941254b1bb608fce2751b58e5af2d2586a4d697";
    hash = "sha256-nTqUmwvuwDHNGUw1qDII6EgA5yQIty+mURw1aABybVQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/waydroid-total-spoof

    # Install both scripts to share directory
    install -Dm755 V2.0.sh $out/share/waydroid-total-spoof/V2.0.sh
    install -Dm755 waydroid.sh $out/share/waydroid-total-spoof/waydroid.sh

    # V2.0 is the recommended script (25 device profiles, performance props)
    makeWrapper $out/share/waydroid-total-spoof/V2.0.sh $out/bin/waydroid-total-spoof \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gnused
          gnugrep
          gawk
          openssl
        ]
      }

    # Legacy script (20 profiles including x86 devices)
    makeWrapper $out/share/waydroid-total-spoof/waydroid.sh $out/bin/waydroid-spoof-legacy \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gnused
          gnugrep
          gawk
          openssl
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Device identity spoofing toolkit for Waydroid (bypass emulator detection)";
    homepage = "https://github.com/lil-xhris/Waydroid-total-spoof";
    license = lib.licenses.unfree; # No license specified in repo
    platforms = lib.platforms.linux;
    mainProgram = "waydroid-total-spoof";
  };
}
