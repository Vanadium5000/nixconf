# snitch - TUI for inspecting network connections (netstat for humans)
# https://github.com/karol-broda/snitch
{
  lib,
  stdenv,
  fetchurl,
}:
let
  version = "0.2.2";

  # Platform-specific sources
  sources = {
    x86_64-linux = {
      url = "https://github.com/karol-broda/snitch/releases/download/v${version}/snitch_${version}_linux_amd64.tar.gz";
      hash = "sha256-L5bGcwa63jAnD7Qk9GL00A5NMxEslG/sDEUR78bj3OE=";
    };
    aarch64-linux = {
      url = "https://github.com/karol-broda/snitch/releases/download/v${version}/snitch_${version}_linux_arm64.tar.gz";
      hash = "sha256-MrSGrVreOCF4PTxPpxUxkCvDPCNiwPCqod3B7yR7GQ8=";
    };
  };

  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "snitch";
  inherit version;

  src = fetchurl {
    inherit (src) url hash;
  };

  # Pre-built binary, no build phase needed
  dontBuild = true;
  dontConfigure = true;

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 snitch $out/bin/snitch
    runHook postInstall
  '';

  meta = {
    description = "TUI for inspecting network connections - netstat for humans";
    homepage = "https://github.com/karol-broda/snitch";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "snitch";
  };
}
