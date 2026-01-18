{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nix-update
    pkgs.git
  ];
  text = ''
    # Navigate to the target directory
    ROOT="$(git rev-parse --show-toplevel)"
    TARGET="$ROOT/modules/_pkgs"
    cd "$TARGET"

    # Create a temporary expression to expose packages for nix-update
    # This avoids relying on flake attribute paths which might require --flake (missing in some nix-update versions)
    cat > packages.nix <<EOF
{ pkgs ? import <nixpkgs> {} }:
{
  daisyui-mcp = pkgs.callPackage ./daisyui-mcp.nix {};
  iloader = pkgs.callPackage ./iloader.nix {};
  niri-screen-time = pkgs.callPackage ./niri-screen-time.nix {};
  pomodoro-for-waybar = pkgs.callPackage ./pomodoro-for-waybar.nix {};
  sideloader = pkgs.callPackage ./sideloader.nix {};
}
EOF

    # Set NIX_PATH so <nixpkgs> can be resolved
    export NIX_PATH=nixpkgs=${pkgs.path}

    echo "Fetching latest package information..."

    # Define packages to update
    PACKAGES=(
      "daisyui-mcp"
      "iloader"
      "niri-screen-time"
      "pomodoro-for-waybar"
      "sideloader"
    )

    UPDATED=()

    for pkg in "''${PACKAGES[@]}"; do
      echo "Checking $pkg..."
      # Try to update using the temporary packages.nix
      if nix-update -f packages.nix "$pkg" --commit; then
        echo "Updated $pkg"
        UPDATED+=("$pkg")
      else
        echo "No update for $pkg or failed."
      fi
    done
    
    # Cleanup
    rm packages.nix

    if [ ''${#UPDATED[@]} -eq 0 ]; then
      echo "No packages updated."
      exit 0
    fi

    echo "----------------------------------------------------------------"
    echo "The following packages were updated:"
    printf '%s\n' "''${UPDATED[@]}"
    echo "----------------------------------------------------------------"
    
    git diff modules/_pkgs

    read -p "Do you want to commit these changes? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add modules/_pkgs
        git commit -m "chore(pkgs): update $(IFS=, ; echo "''${UPDATED[*]}")"
        echo "Committed."
    else
        echo "Changes left in working tree. You can revert them with 'git checkout modules/_pkgs' if desired."
    fi
  '';
}
