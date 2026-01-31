{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nix-update
    pkgs.git
    pkgs.libnotify
    pkgs.findutils
    pkgs.curl
    pkgs.jq
    pkgs.gnused
    pkgs.nix-prefetch-github
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

    # Function to get latest GitHub release tag
    get_latest_release() {
      local owner="$1"
      local repo="$2"
      curl -s "https://api.github.com/repos/$owner/$repo/releases/latest" | jq -r '.tag_name // empty'
    }

    # Function to get latest GitHub tag
    get_latest_tag() {
      local owner="$1"
      local repo="$2"
      curl -s "https://api.github.com/repos/$owner/$repo/tags" | jq -r '.[0].name // empty'
    }

    # Function to get latest commit SHA for a branch
    get_latest_commit() {
      local owner="$1"
      local repo="$2"
      local branch="''${3:-main}"
      curl -s "https://api.github.com/repos/$owner/$repo/commits/$branch" | jq -r '.sha // empty'
    }

    # Function to prefetch GitHub source and get hash
    prefetch_github() {
      local owner="$1"
      local repo="$2"
      local rev="$3"
      nix-prefetch-github "$owner" "$repo" --rev "$rev" 2>/dev/null | jq -r '.hash // .sha256 // empty'
    }

    # Function to prefetch URL and get hash
    prefetch_url() {
      local url="$1"
      nix-prefetch-url "$url" 2>/dev/null | xargs nix-hash --type sha256 --to-sri 2>/dev/null || echo ""
    }

    # Function to update a single hash in a file
    update_hash_in_file() {
      local file="$1"
      local old_hash="$2"
      local new_hash="$3"
      if [ -n "$new_hash" ] && [ "$old_hash" != "$new_hash" ]; then
        sed -i "s|$old_hash|$new_hash|g" "$file"
        return 0
      fi
      return 1
    }

    # Function to update version string in file
    update_version_in_file() {
      local file="$1"
      local old_version="$2"
      local new_version="$3"
      if [ -n "$new_version" ] && [ "$old_version" != "$new_version" ]; then
        sed -i "s|version = \"$old_version\"|version = \"$new_version\"|g" "$file"
        return 0
      fi
      return 1
    }

    # Function to extract value from nix file using regex
    extract_nix_value() {
      local file="$1"
      local pattern="$2"
      grep -oP "$pattern" "$file" | head -1 || echo ""
    }

    # Multi-source update for packages with multiple fetchFromGitHub/fetchurl
    update_multi_source_package() {
      local pkg="$1"
      local file="$pkg.nix"
      local updated=false

      echo "  Attempting multi-source update for $pkg..."

      # Extract all GitHub sources (owner/repo pairs)
      local sources
      sources=$(grep -A5 'fetchFromGitHub' "$file" | grep -E 'owner|repo' | paste - - | \
        sed 's/.*owner = "\([^"]*\)".*repo = "\([^"]*\)".*/\1 \2/' 2>/dev/null || echo "")

      if [ -n "$sources" ]; then
        while IFS=' ' read -r owner repo; do
          [ -z "$owner" ] || [ -z "$repo" ] && continue

          echo "    Processing GitHub source: $owner/$repo"

          # Get current rev/hash from file
          local current_hash
          current_hash=$(grep -A10 "repo = \"$repo\"" "$file" | grep -oP 'hash = "sha256-[^"]+' | head -1 | sed 's/hash = "//' || echo "")

          # Get latest commit
          local latest_rev
          latest_rev=$(get_latest_commit "$owner" "$repo" "main")
          [ -z "$latest_rev" ] && latest_rev=$(get_latest_commit "$owner" "$repo" "master")

          if [ -n "$latest_rev" ]; then
            echo "      Latest commit: ''${latest_rev:0:12}"

            # Prefetch new hash
            local new_hash
            new_hash=$(prefetch_github "$owner" "$repo" "$latest_rev")

            if [ -n "$new_hash" ] && [ "$current_hash" != "$new_hash" ]; then
              echo "      Updating hash: $current_hash -> $new_hash"

              # Update the hash in file
              if [ -n "$current_hash" ]; then
                sed -i "s|$current_hash|$new_hash|g" "$file"
                updated=true
              fi

              # Also update the rev if it's a commit hash
              local current_rev
              current_rev=$(grep -A10 "repo = \"$repo\"" "$file" | grep -oP 'rev = "[^"]+' | head -1 | sed 's/rev = "//' || echo "")
              if [ -n "$current_rev" ] && [ "$current_rev" != "$latest_rev" ]; then
                sed -i "s|rev = \"$current_rev\"|rev = \"$latest_rev\"|g" "$file"
              fi
            else
              echo "      Hash unchanged or prefetch failed"
            fi
          fi
        done <<< "$sources"
      fi

      # Extract fetchurl sources
      local url_sources
      url_sources=$(grep -oP 'url = "[^"]+' "$file" | sed 's/url = "//' || echo "")

      if [ -n "$url_sources" ]; then
        while IFS= read -r url; do
          [ -z "$url" ] && continue
          # Skip interpolated URLs (they contain variable references)
          if echo "$url" | grep -q '\$'; then continue; fi

          echo "    Processing URL source: $url"

          local current_hash
          current_hash=$(grep -A2 "url = \"$url\"" "$file" | grep -oP 'hash = "sha256-[^"]+' | head -1 | sed 's/hash = "//' || echo "")

          if [ -n "$current_hash" ]; then
            local new_hash
            new_hash=$(prefetch_url "$url")

            if [ -n "$new_hash" ] && [ "$current_hash" != "$new_hash" ]; then
              echo "      Updating hash: $current_hash -> $new_hash"
              sed -i "s|$current_hash|$new_hash|g" "$file"
              updated=true
            fi
          fi
        done <<< "$url_sources"
      fi

      if $updated; then
        return 0
      else
        return 1
      fi
    }

    # Update packages with dynamic version URLs (like antigravity-manager)
    update_versioned_url_package() {
      local pkg="$1"
      local file="$pkg.nix"
      local owner="$2"
      local repo="$3"

      echo "  Checking for new release of $owner/$repo..."

      # Get current version from file
      local current_version
      current_version=$(grep -oP 'version = "[^"]+' "$file" | head -1 | sed 's/version = "//' || echo "")

      if [ -z "$current_version" ]; then
        echo "    Could not extract current version"
        return 1
      fi

      echo "    Current version: $current_version"

      # Get latest release
      local latest_tag
      latest_tag=$(get_latest_release "$owner" "$repo")

      if [ -z "$latest_tag" ]; then
        echo "    Could not fetch latest release"
        return 1
      fi

      # Strip 'v' prefix if present for version comparison
      local latest_version="''${latest_tag#v}"
      local latest_version="''${latest_version#V}"

      echo "    Latest version: $latest_version"

      if [ "$current_version" == "$latest_version" ]; then
        echo "    Already up to date"
        return 1
      fi

      echo "    Updating from $current_version to $latest_version"

      # Update version in file
      sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|g" "$file"

      # The URL likely contains the version, so we need to prefetch the new URL
      # Find the URL pattern and substitute version
      local url_pattern
      url_pattern=$(grep -oP 'url = "[^"]+' "$file" | head -1 | sed 's/url = "//' || echo "")

      if [ -n "$url_pattern" ]; then
        # Evaluate the URL with the new version (simple substitution)
        local new_url
        # shellcheck disable=SC2001
        new_url=$(echo "$url_pattern" | sed "s/\''${version}/$latest_version/g")

        echo "    Prefetching new URL: $new_url"

        local new_hash
        new_hash=$(prefetch_url "$new_url")

        if [ -n "$new_hash" ]; then
          local current_hash
          current_hash=$(grep -oP 'hash = "sha256-[^"]+' "$file" | head -1 | sed 's/hash = "//' || echo "")

          if [ -n "$current_hash" ]; then
            echo "    Updating hash: $current_hash -> $new_hash"
            sed -i "s|$current_hash|$new_hash|g" "$file"
          fi
        else
          echo "    Warning: Could not prefetch new hash, version updated but hash may be stale"
        fi
      fi

      return 0
    }

    notify "Scanning for packages..."

    # Dynamically find all .nix files (excluding utility scripts)
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
    $(for pkg in "''${PACKAGES[@]}"; do
      if [ "$pkg" == "antigravity-manager" ]; then
        echo "  $pkg = (pkgs.callPackage ./$pkg.nix {}).unwrapped;"
      elif [ "$pkg" == "sora-watermark-cleaner" ]; then
        # Skip - has complex Python deps that may not eval cleanly
        echo "  # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - complex deps"
      else
        echo "  $pkg = pkgs.callPackage ./$pkg.nix {};"
      fi
    done)
    }
    EOF

    # Set NIX_PATH so <nixpkgs> can be resolved
    export NIX_PATH=nixpkgs=${pkgs.path}

    notify "Updating ''${#PACKAGES[@]} packages..."

    UPDATED=()
    FAILED=()
    SKIPPED=()

    for pkg in "''${PACKAGES[@]}"; do
      echo "================================================================"
      echo "Checking $pkg..."
      
      # Per-package update strategies
      case "$pkg" in
        "antigravity-manager")
          # Has versioned URL - use custom updater
          if update_versioned_url_package "$pkg" "lbjlaq" "Antigravity-Manager"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "dogecoin")
          # Has versioned URL from GitHub releases
          if update_versioned_url_package "$pkg" "dogecoin" "dogecoin"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "quickshell-docs-markdown")
          # Has multiple GitHub sources - use multi-source updater
          if update_multi_source_package "$pkg"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "sora-watermark-cleaner")
          # Complex package with pre-fetched models - use multi-source updater
          if update_multi_source_package "$pkg"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "deep-live-cam")
          # Uses GitHub release tags
          if update_versioned_url_package "$pkg" "hacksider" "Deep-Live-Cam"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "daisyui-mcp"|"pomodoro-for-waybar"|"libreoffice-mcp")
          # Track branches - use nix-update with branch mode
          # These packages pin to latest commit on main/master branch
          set +e
          if nix-update -f packages.nix "$pkg" --version branch; then
            UPDATED+=("$pkg")
          else
            # Fallback to multi-source updater
            if update_multi_source_package "$pkg"; then
              UPDATED+=("$pkg")
            else
              FAILED+=("$pkg")
            fi
          fi
          set -e
          ;;

        "niri-screen-time")
          # Go package with vendorHash - standard nix-update
          set +e
          if nix-update -f packages.nix "$pkg"; then
            UPDATED+=("$pkg")
          else
            FAILED+=("$pkg")
          fi
          set -e
          ;;

        "iloader"|"sideloader")
          # AppImage/binary packages - check for new releases
          set +e
          if nix-update -f packages.nix "$pkg"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          set -e
          ;;

        *)
          # Default: try nix-update first, fallback to multi-source
          set +e
          if nix-update -f packages.nix "$pkg"; then
            UPDATED+=("$pkg")
          else
            if update_multi_source_package "$pkg"; then
              UPDATED+=("$pkg")
            else
              SKIPPED+=("$pkg")
            fi
          fi
          set -e
          ;;
      esac
    done

    # Cleanup
    rm -f packages.nix

    echo "================================================================"
    echo "Summary:"
    echo "  Updated: ''${#UPDATED[@]}"
    echo "  Skipped: ''${#SKIPPED[@]} (already up-to-date or unsupported)"
    echo "  Failed:  ''${#FAILED[@]}"

    if [ ''${#UPDATED[@]} -gt 0 ]; then
      echo ""
      echo "Updated packages:"
      printf '  - %s\n' "''${UPDATED[@]}"
    fi

    if [ ''${#FAILED[@]} -gt 0 ]; then
      echo ""
      echo "Failed packages:"
      printf '  - %s\n' "''${FAILED[@]}"
    fi

    if [ ''${#UPDATED[@]} -eq 0 ]; then
      notify "No packages updated."
      exit 0
    fi

    echo "================================================================"
    echo "Changes:"
    git --no-pager diff .

    # Final notification
    MSG="Updated: $(IFS=', '; echo "''${UPDATED[*]}")"
    notify "$MSG"
  '';
}
