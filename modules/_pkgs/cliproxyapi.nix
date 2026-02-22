{
  unstable,
  fetchFromGitHub,
  lib,
  ...
}:

unstable.buildGo126Module rec {
  pname = "cliproxyapi";
  version = "6.8.22";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "d210be06c2912b87e78781f122e053d21d5ea2b2";
    hash = "sha256-E3UWvAB/9h/iTGs3dbxbrCx2Ml6jxAf7bGKflh4BrHo=";
  };

  vendorHash = "sha256-3h68+GSEvd7tcJOqTjV2KXBXZFX7AWg3r8K3zZe4DnI=";

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
