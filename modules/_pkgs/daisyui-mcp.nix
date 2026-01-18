{ pkgs, ... }:

let
  python = pkgs.python313;
  pythonEnv = python.withPackages (ps: [ ps.fastmcp ]);
in
pkgs.stdenv.mkDerivation {
  pname = "daisyui-mcp";
  version = "1.0.0";

  src = pkgs.fetchFromGitHub {
    owner = "birdseyevue";
    repo = "daisyui-mcp";
    rev = "main";
    hash = "sha256-KCgj39tslAkS6F0+huzNVvsFaLBgbJyLjPa779pn3/s=";
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
