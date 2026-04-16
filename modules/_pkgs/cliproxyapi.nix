{
  unstable,
  fetchFromGitHub,
  lib,
  ...
}:

unstable.buildGo126Module rec {
  pname = "cliproxyapi";
  version = "6.9.28";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-TBSYsH6CW11mQN4Z8Q9wf7piZiggOio8eSejnYUj2Ro=";
  };

  vendorHash = "sha256-qvQO7c/780UWxvM/Lp/KHqcd/pFqzyJx6ILaOeZId7A=";

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
