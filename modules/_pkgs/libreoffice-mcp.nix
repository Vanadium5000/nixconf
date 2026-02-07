{ pkgs, ... }:

let
  # MCP server source from upstream
  mcpSource = pkgs.fetchFromGitHub {
    owner = "WaterPistolAI";
    repo = "libreoffice-mcp";
    rev = "fdd2b0dfeb0372524b637b723332028ba744e47f"; # Pin to specific commit
    hash = "sha256-UPKD4QHtqhVszhaN0T/y6AOJMIeYgd0YFc8eoRS6Ps4=";
  };

  # OooDev LibreOffice extension - bundles all ooo-dev-tools Python dependencies
  # This avoids packaging 50+ Python deps in Nix; installed via unopkg on first run
  # Source: https://extensions.libreoffice.org/en/extensions/show/41700
  ooodevExt = pkgs.fetchurl {
    url = "https://extensions.libreoffice.org/assets/downloads/5120/1748030959/OooDev.oxt";
    hash = "sha256-tcc8W3YmjONNZK5doo9M0kqxTphLYpngE+msRg9GVEg=";
    name = "OooDev.oxt";
  };

  # Nix Python environment with MCP dependencies
  # These packages are mounted into the Flatpak via PYTHONPATH
  # Using python311 to match typical Freedesktop SDK Python version
  pythonEnv = pkgs.python311.withPackages (ps: [
    ps.mcp # Model Context Protocol SDK (v1.15.0+)
    ps.fastapi # Web framework used by MCP server
    ps.python-dotenv # Environment variable loader
    ps.uvicorn # ASGI server (may be needed for some MCP transports)
  ]);

  # Path to Python site-packages for PYTHONPATH injection
  pythonSitePackages = "${pythonEnv}/${pythonEnv.sitePackages}";

  # Wrapper script that runs the MCP server inside Flatpak sandbox
  # Uses hybrid approach: OooDev extension for ooodev.*, Nix packages for mcp/fastapi
  wrapperScript = pkgs.writeShellScript "libreoffice-mcp" ''
        # LibreOffice MCP Server (WaterPistolAI/libreoffice-mcp)
        # Runs inside Flatpak sandbox for UNO module access
        # Connects to LibreOffice via socket on port 2083
        #
        # Architecture:
        # - OooDev.oxt extension provides ooodev.* modules (50+ deps bundled)
        # - Nix Python env provides mcp, fastapi, python-dotenv via PYTHONPATH
        # - Flatpak's Python interpreter runs everything with UNO access

        set -e

        LIBREOFFICE_PORT="''${LIBREOFFICE_PORT:-2083}"
        export LIBREOFFICE_OUTPUT_DIR="''${LIBREOFFICE_OUTPUT_DIR:-$HOME/Documents}"
        MCP_SHARE="@out@/share/libreoffice-mcp"
        OOODEV_EXT="@ooodevExt@"
        PYTHON_SITE_PACKAGES="@pythonSitePackages@"

        # Marker file tracks OooDev extension installation (version-aware)
        OOODEV_MARKER="$HOME/.var/app/org.libreoffice.LibreOffice/.ooodev-ext-installed"
        # Old pip-based marker (cleanup on migration)
        OLD_PIP_MARKER="$HOME/.var/app/org.libreoffice.LibreOffice/.libreoffice-mcp-deps-installed"

        # Check Flatpak LibreOffice is installed
        if ! ${pkgs.flatpak}/bin/flatpak info org.libreoffice.LibreOffice &>/dev/null; then
            echo "Error: LibreOffice Flatpak not installed." >&2
            echo "Install with: flatpak install flathub org.libreoffice.LibreOffice" >&2
            exit 1
        fi

        # Install OooDev extension on first run
        # This provides all ooodev.* modules without needing pip
        if [ ! -f "$OOODEV_MARKER" ]; then
            echo "First run: Installing OooDev extension..."
            mkdir -p "$(dirname "$OOODEV_MARKER")"

            # Check if LibreOffice is running (unopkg requires LO not running)
            # Use pgrep -x for exact process name match to avoid matching ourselves
            if pgrep -x "soffice.bin" > /dev/null 2>&1 || pgrep -x "oosplash" > /dev/null 2>&1; then
                echo "Error: LibreOffice is running. Please close it before first run." >&2
                echo "The OooDev extension cannot be installed while LibreOffice is open." >&2
                exit 1
            fi

            # Install the OooDev extension via unopkg (user-level install)
            # unopkg binary is at /app/libreoffice/program/unopkg inside the Flatpak
            # Note: --shared install fails inside Flatpak (no write access to /app)
            UNOPKG_CMD="/app/libreoffice/program/unopkg"

            # Clean up any partial OooDev installation before attempting fresh install
            if ${pkgs.flatpak}/bin/flatpak run \
                --command="$UNOPKG_CMD" \
                org.libreoffice.LibreOffice \
                list 2>/dev/null | grep -qi "ooodev"; then
                echo "Removing existing OooDev installation..."
                ${pkgs.flatpak}/bin/flatpak run \
                    --command="$UNOPKG_CMD" \
                    org.libreoffice.LibreOffice \
                    remove "org.openoffice.extensions.ooodev" || true
            fi

            if ${pkgs.flatpak}/bin/flatpak run \
                --filesystem=/nix/store:ro \
                --command="$UNOPKG_CMD" \
                org.libreoffice.LibreOffice \
                add "$OOODEV_EXT"; then

                # Verify installation succeeded
                if ${pkgs.flatpak}/bin/flatpak run \
                    --command="$UNOPKG_CMD" \
                    org.libreoffice.LibreOffice \
                    list 2>/dev/null | grep -qi "ooodev\|OooDev"; then
                    touch "$OOODEV_MARKER"
                    echo "OooDev extension installed successfully"

                    # Clean up old pip-based marker if it exists
                    rm -f "$OLD_PIP_MARKER"
                else
                    echo "Error: OooDev extension installation could not be verified" >&2
                    echo "The extension does not appear in 'unopkg list'" >&2
                    echo "" >&2
                    echo "To retry installation:" >&2
                    echo "  rm ~/.var/app/org.libreoffice.LibreOffice/.ooodev-ext-installed" >&2
                    echo "" >&2
                    echo "For manual install:" >&2
                    echo "  flatpak run --filesystem=/nix/store:ro --command=/app/libreoffice/program/unopkg org.libreoffice.LibreOffice add $OOODEV_EXT" >&2
                    exit 1
                fi
            else
                echo "Error: Failed to install OooDev extension" >&2
                echo "Try manually: flatpak run --command=unopkg org.libreoffice.LibreOffice add $OOODEV_EXT" >&2
                exit 1
            fi
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

        # Find OooDev extension's Python modules path
        # The extension installs to a dynamic path with random temp dir name:
        # ~/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/uno_packages/cache/uno_packages/<random>/*.oxt/
        OOODEV_BASE="$HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/uno_packages/cache/uno_packages"
        OOODEV_PIP_PATH=""
        if [ -d "$OOODEV_BASE" ]; then
            # Find the ooodev_tools_pip directory inside the extension
            OOODEV_PIP_PATH=$(find "$OOODEV_BASE" -type d -name "ooodev_tools_pip" 2>/dev/null | head -1)
            if [ -n "$OOODEV_PIP_PATH" ]; then
                echo "Found OooDev modules at: $OOODEV_PIP_PATH"
            else
                echo "Warning: OooDev extension installed but ooodev_tools_pip not found" >&2
            fi
        fi

        # Run MCP server inside Flatpak sandbox (gives access to uno.py)
        # Mount the MCP code read-only, Nix store for Python packages, and Documents read-write
        # PYTHONPATH order:
        # 1. /app/libreoffice/program - uno.py and UNO runtime
        # 2. OooDev extension's ooodev_tools_pip - ooodev.* modules
        # 3. Nix site-packages - mcp, fastapi, python-dotenv
        LO_PROGRAM="/app/libreoffice/program"
        
        # Build PYTHONPATH with OooDev if found
        if [ -n "$OOODEV_PIP_PATH" ]; then
            FULL_PYTHONPATH="$LO_PROGRAM:$OOODEV_PIP_PATH:$PYTHON_SITE_PACKAGES"
        else
            FULL_PYTHONPATH="$LO_PROGRAM:$PYTHON_SITE_PACKAGES"
        fi

        exec ${pkgs.flatpak}/bin/flatpak run \
            --command=python3 \
            --filesystem="$MCP_SHARE:ro" \
            --filesystem=/nix/store:ro \
            --filesystem="$HOME/.var/app/org.libreoffice.LibreOffice:ro" \
            --filesystem="$HOME/Documents:rw" \
            --share=network \
            --env=PYTHONPATH="$FULL_PYTHONPATH" \
            --env=LIBREOFFICE_PORT="$LIBREOFFICE_PORT" \
            --env=LIBREOFFICE_OUTPUT_DIR="$LIBREOFFICE_OUTPUT_DIR" \
            org.libreoffice.LibreOffice \
            -c "
    import sys
    sys.path.insert(0, '$MCP_SHARE')
    # Add OooDev extension's Python modules to sys.path (PYTHONPATH alone isn't respected by UNO import hook)
    ooodev_path = '$OOODEV_PIP_PATH'
    if ooodev_path:
        sys.path.insert(0, ooodev_path)
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

    # Install wrapper script, substituting placeholders with actual paths
    substitute ${wrapperScript} $out/bin/libreoffice-mcp \
      --replace-fail "@out@" "$out" \
      --replace-fail "@ooodevExt@" "${ooodevExt}" \
      --replace-fail "@pythonSitePackages@" "${pythonSitePackages}"
    chmod +x $out/bin/libreoffice-mcp
  '';

  # Integration test procedure (manual):
  # 1. Run: libreoffice-mcp
  # 2. First run should install OooDev extension (requires LibreOffice closed)
  # 3. LibreOffice headless should start on port 2083
  # 4. MCP server should respond to stdio commands
  # 5. Test: echo '{"method":"tools/list"}' | libreoffice-mcp

  meta = {
    description = "MCP server for LibreOffice using OooDev (Writer, Calc, Impress, Draw, Base)";
    homepage = "https://github.com/WaterPistolAI/libreoffice-mcp";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    longDescription = ''
      LibreOffice MCP server that runs inside the Flatpak sandbox for proper
      UNO module access. Requires org.libreoffice.LibreOffice Flatpak to be
      installed.

      Dependencies:
      - OooDev extension: Installed automatically on first run via unopkg
      - Python packages (mcp, fastapi, etc.): Provided by Nix, mounted via PYTHONPATH

      This hybrid approach avoids the need for pip inside the Flatpak sandbox
      while still providing all required Python dependencies.
    '';
  };
}
