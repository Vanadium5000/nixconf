{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nix-update
    pkgs.git
    pkgs.libnotify
  ];
  text = ''
        # Navigate to the target directory
        ROOT="$(git rev-parse --show-toplevel)"
        TARGET="$ROOT/modules/_pkgs"
        cd "$TARGET"

        # Function to send notifications
        notify() {
          if command -v notify-send >/dev/null; then
            notify-send "Update Packages" "$1"
          fi
          echo "$1"
        }

        # Create a temporary expression to expose packages for nix-update
        # This avoids relying on flake attribute paths which might require --flake (missing in some nix-update versions)
        cat > packages.nix <<EOF
    { pkgs ? import <nixpkgs> {} }:
    {
      antigravity-manager = pkgs.callPackage ./antigravity-manager.nix {};
      daisyui-mcp = pkgs.callPackage ./daisyui-mcp.nix {};
      iloader = pkgs.callPackage ./iloader.nix {};
      niri-screen-time = pkgs.callPackage ./niri-screen-time.nix {};
      pomodoro-for-waybar = pkgs.callPackage ./pomodoro-for-waybar.nix {};
      sideloader = pkgs.callPackage ./sideloader.nix {};
    }
    EOF

        # Set NIX_PATH so <nixpkgs> can be resolved
        export NIX_PATH=nixpkgs=${pkgs.path}

        notify "Fetching latest package information..."

        # Define packages to update
    PACKAGES=(
      "antigravity-manager"
      "daisyui-mcp"
          "iloader"
          "niri-screen-time"
          "pomodoro-for-waybar"
          "sideloader"
        )

        UPDATED=()
        FAILED=()

        for pkg in "''${PACKAGES[@]}"; do
          echo "Checking $pkg..."
          
          ARGS=("$pkg")
          
      # Per-package configurations
      case "$pkg" in
        "antigravity-manager")
          # Use specific regex to ignore tags without releases (e.g. .44 tag but .43 release)
          ARGS+=("--url" "https://github.com/lbjlaq/Antigravity-Manager" "--use-version" "latest")
          ;;
        "pomodoro-for-waybar"|"daisyui-mcp")
              # These track branches, so update to latest commit
              ARGS+=("--version" "branch")
              ;;
          esac

          # Try to update using the temporary packages.nix
          if nix-update -f packages.nix "''${ARGS[@]}"; then
            echo "Updated $pkg"
            UPDATED+=("$pkg")
          else
            echo "No update for $pkg or failed."
            FAILED+=("$pkg")
          fi
        done
        
        # Cleanup
        rm packages.nix

        if [ ''${#UPDATED[@]} -eq 0 ]; then
          notify "No packages updated."
          exit 0
        fi

        echo "----------------------------------------------------------------"
        echo "The following packages were updated:"
        printf '%s\n' "''${UPDATED[@]}"
        echo "----------------------------------------------------------------"
        
        # Show diff of the current directory (modules/_pkgs) without pager
        git --no-pager diff .

        # Final notification
        MSG="Updated: $(IFS=', '; echo "''${UPDATED[*]}")"
        notify "$MSG"
  '';
}
