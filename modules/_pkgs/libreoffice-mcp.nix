{ pkgs, ... }:

let
  python = pkgs.python312;
  pythonEnv = python.withPackages (
    ps: with ps; [
      httpx # HTTP client (>=0.28.1) for API communication
      mcp # MCP SDK (>=1.10.1) - Model Context Protocol
      pydantic # Data validation (>=2.0.0)
    ]
  );
in
pkgs.stdenv.mkDerivation {
  pname = "libreoffice-mcp";
  version = "0.1.0-unstable-2026-01-31";

  src = pkgs.fetchFromGitHub {
    owner = "patrup";
    repo = "mcp-libre";
    rev = "edc5123dcd740049c54de9bc9abf8d69b2f1293f"; # Pin to specific commit for reproducibility
    hash = "sha256-J0oXBvn5Bejnn6p6cc4He6lfk+aFnuMSgxJBGhcS6EE=";
  };

  buildInputs = [ pythonEnv ];

  installPhase = ''
        mkdir -p $out/bin $out/share/libreoffice-mcp

        # Copy source files - libremcp.py is the main module
        cp libremcp.py $out/share/libreoffice-mcp/
        cp -r src/* $out/share/libreoffice-mcp/ 2>/dev/null || true

        # Wrapper script - uses Flatpak LibreOffice for headless operations
        # The LIBREOFFICE_PATH env var tells the MCP server how to invoke LibreOffice
        cat > $out/bin/libreoffice-mcp << EOF
    #!/bin/sh
    # LibreOffice MCP Server wrapper
    # Uses Flatpak LibreOffice for document operations (headless mode)
    export LIBREOFFICE_PATH="flatpak run --command=libreoffice org.libreoffice.LibreOffice"
    export PYTHONPATH="$out/share/libreoffice-mcp:\$PYTHONPATH"
    cd $out/share/libreoffice-mcp
    exec ${pythonEnv}/bin/python -c "import libremcp; libremcp.main()" "\$@"
    EOF
        chmod +x $out/bin/libreoffice-mcp
  '';

  meta = {
    description = "MCP server for LibreOffice document manipulation (Writer, Calc, Impress, Draw)";
    homepage = "https://github.com/patrup/mcp-libre";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
