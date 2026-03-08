{ pkgs, ... }:

let
  python = pkgs.python313;
  # HACK: Disable tests for fastmcp due to pytest marker and deprecation errors
  fastmcp = pkgs.python313Packages.fastmcp.overridePythonAttrs (old: {
    doCheck = false;
  });
  pythonEnv = python.withPackages (ps: [ fastmcp ]);
in
pkgs.stdenv.mkDerivation {
  pname = "daisyui-mcp";
  version = "1.1.0-unstable-2026-03-08";

  src = pkgs.fetchFromGitHub {
    owner = "birdseyevue";
    repo = "daisyui-mcp";
    rev = "a1d74e4f2a86124c6e43cb596d73010600beb858";
    hash = "sha256-25y5jSRRWre2g0UaZlp3e5OO9Ma90l2mTt7CQ0TMBus=";
  };

  buildInputs = [
    pythonEnv
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/daisyui-mcp
    cp -r components $out/share/daisyui-mcp/
    cp mcp_server.py $out/share/daisyui-mcp/

    # Create a wrapper script
    echo "#!/bin/sh" > $out/bin/daisyui-mcp
    echo "cd $out/share/daisyui-mcp && exec ${pythonEnv}/bin/python mcp_server.py \"\$@\"" >> $out/bin/daisyui-mcp
    chmod +x $out/bin/daisyui-mcp
  '';
}
