{
  unstable,
  fetchFromGitHub,
  lib,
  ...
}:

unstable.buildGo126Module rec {
  pname = "cliproxyapi";
  version = "6.9.2";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-Qh+5tOc5jI6be1RiA6h5FCEbfsc7AFoAlvLav0xX3IU=";
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
