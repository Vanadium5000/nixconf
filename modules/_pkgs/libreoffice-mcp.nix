{ pkgs, ... }:

let
  # MCP server source from upstream
  mcpSource = pkgs.fetchFromGitHub {
    owner = "WaterPistolAI";
    repo = "libreoffice-mcp";
    rev = "fdd2b0dfeb0372524b637b723332028ba744e47f"; # Pin to specific commit
    hash = "sha256-UPKD4QHtqhVszhaN0T/y6AOJMIeYgd0YFc8eoRS6Ps4=";
  };

  # Python dependencies that need to be installed in Flatpak's Python
  # These are installed on first run and cached in ~/.var/app/org.libreoffice.LibreOffice/
  pipDeps = "mcp ooo-dev-tools python-dotenv fastapi uvicorn";

  # Wrapper script that runs the MCP server inside Flatpak sandbox
  # This gives access to LibreOffice's bundled uno.py module
  wrapperScript = pkgs.writeShellScript "libreoffice-mcp" ''
    # LibreOffice MCP Server (WaterPistolAI/libreoffice-mcp)
    # Runs inside Flatpak sandbox for UNO module access
    # Connects to LibreOffice via socket on port 2083

    set -e

    LIBREOFFICE_PORT="''${LIBREOFFICE_PORT:-2083}"
    export LIBREOFFICE_OUTPUT_DIR="''${LIBREOFFICE_OUTPUT_DIR:-$HOME/Documents}"
    MCP_SHARE="@out@/share/libreoffice-mcp"
    PIP_MARKER="$HOME/.var/app/org.libreoffice.LibreOffice/.libreoffice-mcp-deps-installed"

    # Check Flatpak LibreOffice is installed
    if ! ${pkgs.flatpak}/bin/flatpak info org.libreoffice.LibreOffice &>/dev/null; then
        echo "Error: LibreOffice Flatpak not installed." >&2
        echo "Install with: flatpak install flathub org.libreoffice.LibreOffice" >&2
        exit 1
    fi

    # Install Python dependencies in Flatpak's Python on first run
    # Cached in ~/.var/app/org.libreoffice.LibreOffice/
    if [ ! -f "$PIP_MARKER" ]; then
        echo "First run: Installing Python dependencies in Flatpak environment..."
        mkdir -p "$(dirname "$PIP_MARKER")"

        ${pkgs.flatpak}/bin/flatpak run \
            --command=pip3 \
            org.libreoffice.LibreOffice \
            install --user --quiet ${pipDeps} || {
                echo "Error: Failed to install Python dependencies" >&2
                echo "Try manually: flatpak run --command=pip3 org.libreoffice.LibreOffice install ${pipDeps}" >&2
                exit 1
            }

        touch "$PIP_MARKER"
        echo "Dependencies installed successfully"
    fi

    # Start LibreOffice headless if socket not already listening
    if ! ${pkgs.netcat}/bin/nc -z localhost "$LIBREOFFICE_PORT" 2>/dev/null; then
        echo "Starting LibreOffice headless on port $LIBREOFFICE_PORT..."

        ${pkgs.flatpak}/bin/flatpak run \
            org.libreoffice.LibreOffice \
            --headless \
            --accept="socket,host=localhost,port=$LIBREOFFICE_PORT;urp;" &

        # Wait for socket to become available (up to 15 seconds for cold start)
        for i in $(seq 1 15); do
            sleep 1
            if ${pkgs.netcat}/bin/nc -z localhost "$LIBREOFFICE_PORT" 2>/dev/null; then
                echo "LibreOffice ready on port $LIBREOFFICE_PORT"
                break
            fi
            if [ "$i" -eq 15 ]; then
                echo "Warning: LibreOffice may not be ready yet (timeout after 15s)" >&2
            fi
        done
    else
        echo "Using existing LibreOffice instance on port $LIBREOFFICE_PORT"
    fi

    # Run MCP server inside Flatpak sandbox (gives access to uno.py)
    # Mount the MCP code read-only and Documents read-write
    exec ${pkgs.flatpak}/bin/flatpak run \
        --command=python3 \
        --filesystem="$MCP_SHARE:ro" \
        --filesystem="$HOME/Documents:rw" \
        --share=network \
        --env=LIBREOFFICE_PORT="$LIBREOFFICE_PORT" \
        --env=LIBREOFFICE_OUTPUT_DIR="$LIBREOFFICE_OUTPUT_DIR" \
        org.libreoffice.LibreOffice \
        -c "
import sys
sys.path.insert(0, '$MCP_SHARE')
import uno  # Initialize UNO runtime from Flatpak's LibreOffice
from libreoffice import mcp
mcp.run()
" "$@"
  '';
in
pkgs.stdenv.mkDerivation {
  pname = "libreoffice-mcp";
  version = "0.1.0-unstable-2026-02-01";

  src = mcpSource;

  # No build-time LibreOffice dependency - we use Flatpak at runtime
  nativeBuildInputs = [ ];

  # Patch the upstream bug: log_level="INFO" should be log_level=20 (logging.INFO)
  patchPhase = ''
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
    longDescription = ''
      LibreOffice MCP server that runs inside the Flatpak sandbox for proper
      UNO module access. Requires org.libreoffice.LibreOffice Flatpak to be
      installed. On first run, installs Python dependencies (mcp, ooodev, etc.)
      into the Flatpak's user Python environment.
    '';
  };
}
