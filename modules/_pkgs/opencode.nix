{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  bun,
}:

let
  pname = "opencode";
  version = "1.15.5";
  rev = "v${version}";
  srcRev = "d7a6e1daaf2271bcd0b611fbb27d4956806e475a";
  shortRev = builtins.substring 0 7 srcRev;

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    inherit rev;
    hash = "sha256-HZiqia9QzkJMfRQ6bzFBsiGXNHv1WFLUdwhekE+rXM8=";
  };

  releaseAssets = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-v2912gibIgc7zyN1TMO+NR9xM2MWTlvc0+SVAcgRscU=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-piROzOA/MDqJRfrjMPF5ZEafwHgPo1Vc3oD7l6xG8vs=";
    };
  };

  nodeModulesHashes = {
    x86_64-linux = "sha256-FI1mX42vJuYdUDdWevlfHz+OcYkDn/I/HUbHE/jdQvs=";
    aarch64-linux = "sha256-3CQzzKnh/4Zf5vyn56yR5P3ULsW7K7Fr8/RQpekEJDk=";
    aarch64-darwin = "sha256-XPDVHMxlPpXlf43BRqNnwF809unk6iE8tvd0o92d0/w=";
    x86_64-darwin = "sha256-dFXTi13RSgL62lMsep1EoE/KSEPF7Oh31PVdxW1tkzg=";
  };

  asset =
    releaseAssets.${stdenv.hostPlatform.system}
      or (throw "opencode: unsupported system ${stdenv.hostPlatform.system}");

  releaseTarball = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/${rev}/opencode-linux-${asset.arch}.tar.gz";
    inherit (asset) hash;
  };

  nodeModules = stdenv.mkDerivation {
    pname = "opencode-node_modules";
    version = "${version}+${shortRev}";
    inherit src;

    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -R packages/opencode/package.json package.json bun.lock nix/hashes.json $out/

      runHook postInstall
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = nodeModulesHashes.${stdenv.hostPlatform.system} or lib.fakeHash;

    meta.platforms = builtins.attrNames nodeModulesHashes;
  };
in
stdenv.mkDerivation (finalAttrs: {
  inherit
    pname
    version
    src
    nodeModules
    ;

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack

    tar -xzf ${releaseTarball}

    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 opencode $out/bin/opencode



    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/opencode --version | grep -Fx ${lib.escapeShellArg (lib.getVersion bun)}

    runHook postInstallCheck
  '';

  passthru = {
    jsonschema = null;
    inherit nodeModules releaseTarball;
  };

  meta = {
    description = "The open source coding agent";
    homepage = "https://opencode.ai";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/${rev}";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames releaseAssets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
