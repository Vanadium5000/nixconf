{
  buildGo126Module,
  fetchFromGitHub,
  lib,
  ...
}:

buildGo126Module rec {
  pname = "cliproxyapi";
  version = "7.2.113";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-aget6PRnWkzNy/QAG54qCRjHfTRui3srplM+U73Hlbc=";
  };

  vendorHash = "sha256-CrDp7MOr+AwJUhTovklXx3F1yaktQlvD7VYhYSY6VvY=";

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
