{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nix-update
    pkgs.git
    pkgs.libnotify
    pkgs.findutils
  ];
  text = ''
    set -e

    # Navigate to the target directory
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      ROOT="$(git rev-parse --show-toplevel)"
      TARGET="$ROOT/modules/_pkgs"
      cd "$TARGET"
    else
      echo "Error: Not in a git repository."
      exit 1
    fi

    # Function to send notifications
    notify() {
      if command -v notify-send >/dev/null; then
        notify-send "Update Packages" "$1"
      fi
      echo "$1"
    }

    notify "Scanning for packages..."

    # Dynamically find all .nix files (excluding this script and the temp file)
    # We use mapfile to handle filenames safely
    mapfile -t FILES < <(find . -maxdepth 1 -name "*.nix" -not -name "update-pkgs.nix" -not -name "packages.nix" -printf "%f\n" | sort)

    if [ ''${#FILES[@]} -eq 0 ]; then
      notify "No packages found to update."
      exit 0
    fi

    PACKAGES=()
    for file in "''${FILES[@]}"; do
      PACKAGES+=("''${file%.nix}")
    done

    # Create a temporary expression to expose packages for nix-update
    cat > packages.nix <<EOF
    { pkgs ? import <nixpkgs> {} }:
    {
    $(for pkg in "''${PACKAGES[@]}"; do echo "  $pkg = pkgs.callPackage ./$pkg.nix {};"; done)
    }
    EOF

    # Set NIX_PATH so <nixpkgs> can be resolved
    export NIX_PATH=nixpkgs=${pkgs.path}

    notify "Updating ''${#PACKAGES[@]} packages..."

    UPDATED=()
    FAILED=()

    for pkg in "''${PACKAGES[@]}"; do
      echo "----------------------------------------------------------------"
      echo "Checking $pkg..."
      
      ARGS=("$pkg")
      
      # Per-package configurations and overrides
      case "$pkg" in
        "antigravity-manager")
          # Use specific regex to ignore tags without releases (e.g. .44 tag but .43 release)
          # Target .unwrapped to ensure hash updates correctly
          ARGS=("antigravity-manager.unwrapped")
          ARGS+=("--url" "https://github.com/lbjlaq/Antigravity-Manager" "--use-github-releases")
          ;;
        "daisyui-mcp"|"pomodoro-for-waybar")
          # These track branches/unstable, so update to latest commit
          ARGS+=("--version" "branch")
          ;;
        "quickshell-docs-markdown")
          # Has multiple sources and uses 'master'. 
          # Attempt to update to latest commit on branch to replace 'master' with hash
          ARGS+=("--version" "branch")
          ;;
        "niri-screen-time")
           # Standard update. Note: vendorHash update might be tricky or unsupported 
           # depending on nix-update version/capabilities, but we let it try.
           ;;
        *)
          # Default behavior for others (like iloader, sideloader)
          ;;
      esac

      # Try to update using the temporary packages.nix
      # We use set +e here to prevent script from exiting on single package failure
      set +e
      if nix-update -f packages.nix "''${ARGS[@]}"; then
        echo "Successfully updated $pkg"
        UPDATED+=("$pkg")
      else
        echo "Failed to update $pkg"
        FAILED+=("$pkg")
      fi
      set -e
    done

    # Cleanup
    rm packages.nix

    echo "----------------------------------------------------------------"
    echo "Summary:"
    echo "Updated: ''${#UPDATED[@]}"
    echo "Failed:  ''${#FAILED[@]}"

    if [ ''${#FAILED[@]} -gt 0 ]; then
      echo "Failed packages:"
      printf ' - %s\n' "''${FAILED[@]}"
    fi

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
