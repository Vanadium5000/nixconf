{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  nodejs,
  ...
}:

stdenv.mkDerivation rec {
  pname = "openchamber";
  version = "1.8.5";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/openchamber-web-${version}.tgz";
    hash = "sha256-QT0PEhYeQpMLVcJi4qyvFm9DicrKPDgKevuMQDu2BxQ=";
  };

  nativeBuildInputs = [
    makeWrapper
  ];

  # The source is a tarball containing the pre-built web package
  # It usually unpacks into a 'package' directory or similar
  unpackPhase = ''
    mkdir -p source
    tar -xzf $src -C source --strip-components=1
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/openchamber $out/bin

    # Copy the unpacked contents
    cp -r source/* $out/share/openchamber/
    
    # Create the wrapper
    # The CLI entry point in the npm package is usually bin/cli.js
    makeWrapper ${nodejs}/bin/node $out/bin/openchamber \
      --add-flags "$out/share/openchamber/bin/cli.js" \
      --set NODE_PATH "$out/share/openchamber/node_modules"

    runHook postInstall
  '';

  meta = {
    description = "Desktop and web interface for OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.unix;
    mainProgram = "openchamber";
  };
}
