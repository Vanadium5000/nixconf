{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  python3,
}:

buildNpmPackage rec {
  pname = "acp-chat";
  version = "0.1.16";

  src = fetchFromGitHub {
    owner = "formulahendry";
    repo = "acp-ui";
    rev = "v${version}";
    hash = "sha256-hJZIR3Py3Ihp64FZ9LJY96gDNVqHZ/9fDZ7CghB7Abg=";
  };

  npmDepsHash = "sha256-0aEvlOkYA60zBOzGMgTb2IHqjKK8MSDrY1lZkaBpVrQ=";

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    runHook preBuild

    npm run build:web

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/acp-ui" "$out/bin"
    cp -a dist-web/. "$out/share/acp-ui/"

    makeWrapper ${python3}/bin/python "$out/bin/acp-chat" \
      --add-flags "-m http.server --directory $out/share/acp-ui"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -f "$out/share/acp-ui/index.html"
    test -d "$out/share/acp-ui/assets"
    test -x "$out/bin/acp-chat"

    runHook postInstallCheck
  '';

  meta = {
    description = "Modern web client for Agent Client Protocol agents";
    homepage = "https://github.com/formulahendry/acp-ui";
    license = lib.licenses.mit;
    mainProgram = "acp-chat";
    platforms = lib.platforms.linux;
  };
}
