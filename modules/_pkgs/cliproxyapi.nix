{
  unstable,
  fetchFromGitHub,
  lib,
  ...
}:

unstable.buildGoModule rec {
  pname = "cliproxyapi";
  version = "6.8.22";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-ZnpbMmx1ZVgtsWNNVDnGn2kyYVm/1dUkRAFuiQ/EDxY=";
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
