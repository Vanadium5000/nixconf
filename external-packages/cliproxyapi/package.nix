{
  buildGo126Module,
  fetchFromGitHub,
  lib,
  ...
}:

buildGo126Module rec {
  pname = "cliproxyapi";
  version = "7.2.22";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-iabSRs+qIsnz1r/rg3AnD8pqnzDwyKdFvpfKWyZ0+DU=";
  };

  vendorHash = "sha256-vQU3hLDga5PMUwH4KSB3T5sZ1uPUgHQHeyQGJTKHIYs=";

  # go mod download via proxy.golang.org can fail mid-FOD with HTTP/2
  # INTERNAL_ERROR stream resets; force HTTP/1.1 only for the modules fetch.
  # Source: https://github.com/golang/go/issues/51323
  overrideModAttrs = _: {
    env.GODEBUG = "http2client=0";
  };

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
