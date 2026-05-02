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
  version = "1.1.0-unstable-2026-04-30";

  src = pkgs.fetchFromGitHub {
    owner = "birdseyevue";
    repo = "daisyui-mcp";
    rev = "cc651b1ffc0ab9d9fdf3e24d9db9e87bef6b01cc";
    hash = "sha256-yIr73D5MR45KhfCN+dE+IxkF+ZaXu/0VKRmXnuXOlsU=";
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
