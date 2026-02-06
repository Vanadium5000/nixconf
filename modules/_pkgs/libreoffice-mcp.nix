{ pkgs, ... }:

let
  python = pkgs.python312;

  # types-uno-script - Type stubs for UNO scripting
  types-uno-script = python.pkgs.buildPythonPackage {
    pname = "types-uno-script";
    version = "0.1.1";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8d/21/aca114495b60b70b0143324291f39f67b30ab3776a6fb65c79370194c7db/types_uno_script-0.1.1-py3-none-any.whl";
      sha256 = "092f710bd187825957ec67ee1bd2c8f7094b4d4a728966e70d3870239656407a";
    };

    dependencies = [ python.pkgs.typing-extensions ];

    meta = {
      description = "Type stubs for UNO scripting";
      homepage = "https://pypi.org/project/types-uno-script/";
      license = pkgs.lib.licenses.asl20;
    };
  };

  # types-unopy - Type stubs for UNO Python bindings
  types-unopy = python.pkgs.buildPythonPackage {
    pname = "types-unopy";
    version = "2.0.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/3d/51/0717c18e667d53cff55b30af07ccd00f4bdbce9ab278fcc57724d340f1f3/types_unopy-2.0.0-py3-none-any.whl";
      sha256 = "748673362338851088d7ab88b51132c5f42a4e56600a55c27448b44327b023bf";
    };

    dependencies = [
      types-uno-script
      python.pkgs.typing-extensions
    ];

    meta = {
      description = "Type stubs for UNO Python bindings";
      homepage = "https://pypi.org/project/types-unopy/";
      license = pkgs.lib.licenses.asl20;
    };
  };

  # ooouno - LibreOffice UNO type definitions
  ooouno = python.pkgs.buildPythonPackage {
    pname = "ooouno";
    version = "3.0.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/f9/3d/d7f5f71958020e945f5a9c2923fc5d4f473d5ab92af4c61eb09f8014dc45/ooouno-3.0.0-py3-none-any.whl";
      sha256 = "237af5c39c41892e00dacb7d89c18b62025af080c96579bb3c24051f0113fd65";
    };

    dependencies = [
      types-unopy
      python.pkgs.typing-extensions
    ];

    meta = {
      description = "LibreOffice UNO type definitions for Python";
      homepage = "https://pypi.org/project/ooouno/";
      license = pkgs.lib.licenses.asl20;
    };
  };

  # ooo-dev-tools (ooodev) - Pythonic wrapper for LibreOffice UNO API
  ooodev = python.pkgs.buildPythonPackage {
    pname = "ooo-dev-tools";
    version = "0.53.4";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/91/0c/b298802ac969215cd9b36f1a28da3bc28a2dc2b3ac4d86a9a1f7fd3706e6/ooo_dev_tools-0.53.4-py3-none-any.whl";
      sha256 = "fa6e2de28dafff21aca2890413424a3fd1c4eb0fb846b2b23579f8d2e78882a9";
    };

    dependencies = [
      ooouno
      python.pkgs.typing-extensions
    ];

    # Skip tests - requires running LibreOffice instance
    doCheck = false;

    meta = {
      description = "Pythonic wrapper for LibreOffice UNO API";
      homepage = "https://github.com/Amourspirit/python_ooo_dev_tools";
      license = pkgs.lib.licenses.asl20;
    };
  };

  pythonEnv = python.withPackages (ps: [
    ps.mcp # MCP SDK - Model Context Protocol
    ooodev # OooDev - Pythonic LibreOffice UNO API wrapper (custom package above)
    ps.python-dotenv # Environment variable loading
    ps.fastapi # HTTP server for MCP
    ps.uvicorn # ASGI server
  ]);

  # Pre-built wrapper script using writeShellScript for proper escaping
  wrapperScript = pkgs.writeShellScript "libreoffice-mcp" ''
    # LibreOffice MCP Server (WaterPistolAI/libreoffice-mcp)
    # Uses OooDev for Pythonic LibreOffice API access
    # Requires LibreOffice running with socket listener on port 2083

    set -e

    export LIBREOFFICE_PORT="''${LIBREOFFICE_PORT:-2083}"
    export LIBREOFFICE_OUTPUT_DIR="''${LIBREOFFICE_OUTPUT_DIR:-$HOME/Documents}"

    # Add Java to PATH (LibreOffice needs it for some features)
    export PATH="${pkgs.jre_minimal}/bin:$PATH"

    # Find LibreOffice installation and set up UNO paths
    # NixOS libreoffice package location
    LO_PATH="${pkgs.libreoffice}/lib/libreoffice"
    if [ ! -d "$LO_PATH" ]; then
        # Try common system paths
        for path in /usr/lib/libreoffice /usr/lib64/libreoffice /opt/libreoffice*; do
            if [ -d "$path" ]; then
                LO_PATH="$path"
                break
            fi
        done
    fi

    if [ ! -d "$LO_PATH" ]; then
        echo "Error: LibreOffice installation not found" >&2
        exit 1
    fi

    # Set up UNO Python environment
    # LibreOffice bundles its own Python with uno module
    export URE_BOOTSTRAP="file://$LO_PATH/program/fundamentalrc"
    export UNO_PATH="$LO_PATH/program"

    # Add LibreOffice's Python uno module to PYTHONPATH
    # CRITICAL: LibreOffice's program dir must be FIRST so uno.py is found
    # before ooodev tries to import com.sun.star.* types
    export PYTHONPATH="$LO_PATH/program:@out@/share/libreoffice-mcp:$PYTHONPATH"

    # Start LibreOffice in headless mode with socket if not already running
    if ! pgrep -f "soffice.*accept=socket" > /dev/null 2>&1; then
        echo "Starting LibreOffice in headless mode on port $LIBREOFFICE_PORT..."

        # Clean stale profile to avoid NoSuchElementException from version mismatch
        LO_PROFILE="/tmp/libreoffice-mcp-$(id -u)"
        rm -rf "$LO_PROFILE"

        # Use isolated user profile to avoid crashes from incompatible user config
        # (e.g., registrymodifications.xcu from different LO version)
        "$LO_PATH/program/soffice" \
            --headless \
            "-env:UserInstallation=file://$LO_PROFILE" \
            --accept="socket,host=localhost,port=$LIBREOFFICE_PORT;urp;" &
        # Wait for LibreOffice to start accepting connections
        sleep 3
    fi

    cd @out@/share/libreoffice-mcp
    exec ${pythonEnv}/bin/python -c "
import uno  # Initialize UNO runtime BEFORE ooodev imports com.sun.star types
from libreoffice import mcp
mcp.run()
" "$@"
  '';
in
pkgs.stdenv.mkDerivation {
  pname = "libreoffice-mcp";
  version = "0.1.0-unstable-2026-02-01";

  src = pkgs.fetchFromGitHub {
    owner = "WaterPistolAI";
    repo = "libreoffice-mcp";
    rev = "fdd2b0dfeb0372524b637b723332028ba744e47f"; # Pin to specific commit
    hash = "sha256-UPKD4QHtqhVszhaN0T/y6AOJMIeYgd0YFc8eoRS6Ps4=";
  };

  buildInputs = [ pythonEnv ];

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # Patch the upstream bug: log_level="INFO" should be log_level=20 (logging.INFO)
  patchPhase = ''
    # Use sed for robust replacement (handles potential whitespace differences)
    sed -i -E 's/log_level\s*=\s*"INFO"/log_level=20/g' libreoffice.py
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/libreoffice-mcp

    # Copy the patched MCP server module
    cp libreoffice.py $out/share/libreoffice-mcp/

    # Install wrapper script, substituting @out@ placeholder with actual path
    substitute ${wrapperScript} $out/bin/libreoffice-mcp \
      --replace-fail "@out@" "$out"
    chmod +x $out/bin/libreoffice-mcp
  '';

  meta = {
    description = "MCP server for LibreOffice using OooDev (Writer, Calc, Impress, Draw, Base)";
    homepage = "https://github.com/WaterPistolAI/libreoffice-mcp";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
