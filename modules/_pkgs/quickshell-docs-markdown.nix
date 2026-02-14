{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  just,
  ...
}:

let
  # Pin quickshell src based on flake.lock
  quickshellSrc = fetchFromGitHub {
    owner = "quickshell-mirror";
    repo = "quickshell";
    rev = "dacfa9de829ac7cb173825f593236bf2c21f637e";
    hash = "sha256-ngXnN5YXu+f45+QGYNN/VEBMQmcBCYGRCqwaK8cxY1s=";
  };

  # Source for the documentation repo
  docsSrc = fetchFromGitHub {
    owner = "quickshell-mirror";
    repo = "quickshell-docs";
    rev = "2fa8ed73c0b22c512b2e3fe4e57a8531d2e58694";
    hash = "sha256-gAZumUNxMZXOQrv6rmH9Yi1RDmywJgLIV0UkGqr1Fk4=";
  };

  # Build the typegen tool from source
  typegen = rustPlatform.buildRustPackage {
    pname = "typegen";
    version = "0.1.0";
    # We use the typegen directory from the fetched docs source
    src = "${docsSrc}/typegen";
    cargoHash = "sha256-vLj/EKfBzlfRdmVr114evJS+Owzz4PdARNGBE3aPUo4=";
  };

in
stdenv.mkDerivation {
  pname = "quickshell-docs-markdown";
  version = "0-unstable-2025-07-01";

  src = docsSrc;

  nativeBuildInputs = [
    just
    typegen
  ];

  buildPhase = ''
    # Point to the pinned quickshell source for type generation
    # We use the typegen binary built above
    SRC_PATH="${quickshellSrc}/src" TYPEGEN=typegen just typedocs
  '';

  installPhase = ''
    mkdir -p $out
    cp -r ./content/* $out/
  '';

  meta = with lib; {
    description = "Quickshell documentation in raw markdown format (bundled)";
    homepage = "https://quickshell.outfoxxed.me";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
