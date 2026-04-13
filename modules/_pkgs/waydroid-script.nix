{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  # Runtime dependencies required by the upstream script when unpacking images.
  # Keep them in PATH via the wrapper so NixOS users do not depend on mutable host state.
  gnutar,
  lzip,
  util-linux,
  e2fsprogs,
  nix-update-script,
}:

let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      tqdm
      requests
      inquirerpy
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "waydroid-script";
  # Upstream does not publish releases or tags, so track the vetted main-branch
  # commit date in the standard unstable version format.
  version = "0-unstable-2026-01-05";

  src = fetchFromGitHub {
    owner = "casualsnek";
    repo = "waydroid_script";
    rev = "d5289cfd8929e86e7f0dc89ecadcef8b66930eec";
    hash = "sha256-zSHZlhHJHWZRE3I5pYWhD4o8aNpa8rTiEtl2qJTuRjw=";
  };

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    patchShebangs main.py
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec/waydroid-script
    cp -r . $out/libexec/waydroid-script

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/waydroid-script \
      --add-flags "$out/libexec/waydroid-script/main.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          gnutar
          lzip
          util-linux
          e2fsprogs
        ]
      }

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version"
      "branch=main"
    ];
  };

  meta = with lib; {
    description = "Python helper for adding GApps, Magisk, libhoudini, and libndk to Waydroid";
    homepage = "https://github.com/casualsnek/waydroid_script";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "waydroid-script";
    maintainers = [ ];
  };
}
