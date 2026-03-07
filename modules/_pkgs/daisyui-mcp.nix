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
  version = "1.0.1-unstable-2026-03-07";

  src = pkgs.fetchFromGitHub {
    owner = "birdseyevue";
    repo = "daisyui-mcp";
    rev = "55564c9181a41086039c339936f44c76aa225288";
    hash = "sha256-xuh/1bx5EikbgCxDyGzHtHWRDFSzPi7HpXhOqrTQXXw=";
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
