{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nvfetcher
    pkgs.git
  ];
  text = ''
    # Navigate to the repo root
    ROOT="$(git rev-parse --show-toplevel)"
    TARGET="$ROOT/modules/_pkgs"

    if [ ! -f "$TARGET/nvfetcher.toml" ]; then
      echo "Error: nvfetcher.toml not found in $TARGET"
      exit 1
    fi

    # Remove state file to force a full re-check
    rm -f "$TARGET/_sources/generated.json"

    # Snapshot current generated.nix
    cp "$TARGET/_sources/generated.nix" "$TARGET/generated.nix.bak" 2>/dev/null || touch "$TARGET/generated.nix.bak"

    echo "Updating packages in $TARGET..."
    cd "$TARGET"
    nvfetcher -c nvfetcher.toml -o _sources "$@"
    
    echo "----------------------------------------------------------------"
    if cmp -s "_sources/generated.nix" "generated.nix.bak"; then
       echo "No updates found."
       rm "generated.nix.bak"
    else
       echo "Updates found!"
       git diff --no-index "generated.nix.bak" "_sources/generated.nix" || true
       
       read -p "Do you want to keep these changes? [Y/n] " -n 1 -r
       echo
       if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
           echo "Reverting changes..."
           mv "generated.nix.bak" "_sources/generated.nix"
           echo "Updates discarded."
       else
           rm "generated.nix.bak"
           echo "Updates kept."
       fi
    fi
  '';
}
