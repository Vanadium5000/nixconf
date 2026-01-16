{ pkgs, ... }:

let
  python = pkgs.python313;
in
pkgs.stdenv.mkDerivation {
  pname = "daisyui-mcp";
  version = "unstable-2024-01-16";

  src = pkgs.fetchFromGitHub {
    owner = "birdseyevue";
    repo = "daisyui-mcp";
    rev = "main";
    hash = "sha256-KCgj39tslAkS6F0+huzNVvsFaLBgbJyLjPa779pn3/s=";
  };

  buildInputs = [
    (python.withPackages (ps: [ ps.fastmcp ]))
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/daisyui-mcp
    cp -r components $out/share/daisyui-mcp/
    cp mcp_server.py $out/share/daisyui-mcp/

    # Create a wrapper script
    echo "#!/bin/sh" > $out/bin/daisyui-mcp
    echo "cd $out/share/daisyui-mcp && exec ${python}/bin/python mcp_server.py \"\$@\"" >> $out/bin/daisyui-mcp
    chmod +x $out/bin/daisyui-mcp
  '';
}
