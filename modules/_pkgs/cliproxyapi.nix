{
  buildGo126Module,
  fetchFromGitHub,
  lib,
  ...
}:

buildGo126Module rec {
  pname = "cliproxyapi";
  version = "7.1.55";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-PolUWqtiwWd+ApGaE8F/ijcvlSjnxfyBKI/9hmRTC6E=";
  };

  vendorHash = "sha256-AIue9XBsfsKGClRLB1DCME+36crapnOdQrEICFYG1a0=";

  postPatch = ''
    if grep -q 'github.com/router-for-me/CLIProxyAPI/v6' sdk/cliproxy/auth/request_auth_prepare_test.go; then
      substituteInPlace sdk/cliproxy/auth/request_auth_prepare_test.go \
        --replace-fail 'github.com/router-for-me/CLIProxyAPI/v6' 'github.com/router-for-me/CLIProxyAPI/v7'
    fi
  '';

  subPackages = [ "cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  postInstall = ''
    mv $out/bin/server $out/bin/cliproxyapi
  '';
  meta = {
    description = "Proxy server that wraps Gemini CLI, Claude Code, etc. into an OpenAI-compatible API";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cliproxyapi";
    platforms = lib.platforms.unix;
  };
}
