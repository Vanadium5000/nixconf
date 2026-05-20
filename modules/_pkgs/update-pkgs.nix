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
    pkgs.gum
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

          cleanup() {
            rm -f packages.nix
          }

          trap cleanup EXIT
          trap 'cleanup; exit 130' INT TERM HUP

          # Function to send notifications
          notify() {
            if command -v notify-send >/dev/null; then
              notify-send "Update Packages" "$1"
            fi
            echo "$1"
          }

          IMPORTANT_LIGHT_PACKAGES=(
            acp-chat
            omniroute
            openchamber-web
            cpa-usage-keeper
            services-auth-gateway
            niri-screen-time
            daisyui-mcp
            mattpocock-skills
          )

          IMPORTANT_MEDIUM_PACKAGES=(
            cliproxyapi
            brave-origin
            patchright
            iloader
            playwright-cli
            cake-wallet-flatpak
            limux
            dogecoin
            antigravity-manager
            waydroid-script
            waydroid-total-spoof
            sideloader
            snitch
            quickshell-docs-markdown
          )

          HEAVY_LESS_IMPORTANT_PACKAGES=(
            wallpapers
            aptos-fonts
          )

          package_summary() {
            local label="$1"
            shift

            gum style \
              --foreground 212 \
              --bold \
              "$label"
            printf '  '
            printf '%s' "$1"
            shift || true
            for pkg in "$@"; do
              printf '  •  %s' "$pkg"
            done
            printf '\n\n'
          }

          show_update_menu_intro() {
            gum style \
              --border rounded \
              --border-foreground 63 \
              --padding "1 2" \
              --margin "1 0" \
              --foreground 255 \
              --bold \
              "update-pkgs" \
              "Choose which package set to update" \
              "No input for 5 seconds selects Important + light."

            package_summary "Important + light  · default" "''${IMPORTANT_LIGHT_PACKAGES[@]}"
            package_summary "Important + medium" "''${IMPORTANT_MEDIUM_PACKAGES[@]}"
            package_summary "Heavy + less important" "''${HEAVY_LESS_IMPORTANT_PACKAGES[@]}"
          }

          select_update_packages() {
            local choice=""
            local status=0

            if [ ! -t 0 ]; then
              SELECTED_LABEL="Important + light"
              SELECTED_PACKAGES=("''${IMPORTANT_LIGHT_PACKAGES[@]}")
              return
            fi

            show_update_menu_intro

            set +e
            choice=$(gum choose \
              --header "Update set" \
              --height 5 \
              --timeout 5s \
              --cursor "➜ " \
              --cursor.foreground 212 \
              --header.foreground 63 \
              --item.foreground 246 \
              --selected.foreground 212 \
              "Important + light" \
              "Important + medium" \
              "Heavy + less important")
            status=$?
            set -e

            if [ "$status" -eq 124 ]; then
              choice="Important + light"
            elif [ "$status" -ne 0 ]; then
              gum style --foreground 196 "Cancelled."
              exit "$status"
            fi

            # Timeout/no movement defaults to the first and safest group.
            case "$choice" in
              "Important + light"|"")
                SELECTED_LABEL="Important + light"
                SELECTED_PACKAGES=("''${IMPORTANT_LIGHT_PACKAGES[@]}")
                ;;
              "Important + medium")
                SELECTED_LABEL="Important + medium"
                SELECTED_PACKAGES=("''${IMPORTANT_MEDIUM_PACKAGES[@]}")
                ;;
              "Heavy + less important")
                SELECTED_LABEL="Heavy + less important"
                SELECTED_PACKAGES=("''${HEAVY_LESS_IMPORTANT_PACKAGES[@]}")
                ;;
            esac

            gum style --foreground 82 --bold "Selected: $SELECTED_LABEL"
            printf '  - %s\n' "''${SELECTED_PACKAGES[@]}"
            echo ""
          }

          contains_package() {
            local needle="$1"
            shift
            local pkg
            for pkg in "$@"; do
              [ "$pkg" = "$needle" ] && return 0
            done
            return 1
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

          # Function to get latest npm package version
          get_latest_npm_version() {
            local package="$1"
            curl -s "https://registry.npmjs.org/$package/latest" | jq -r '.version // empty'
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

          prefetch_npm_tarball() {
            local package="$1"
            local version="$2"
            prefetch_url "https://registry.npmjs.org/$package/-/$package-$version.tgz"
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

          package_file() {
            local pkg="$1"
            echo "$pkg.nix"
          }

          # Multi-source update for packages with multiple fetchFromGitHub/fetchurl
          update_multi_source_package() {
            local pkg="$1"
            local file
            file=$(package_file "$pkg")
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
            local file
            file=$(package_file "$pkg")
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
              new_url=$(echo "$url_pattern" | sed -e "s/\''${version}/$latest_version/g" -e "s/\''${finalAttrs.version}/$latest_version/g")

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

        set_first_hash_after() {
          local file="$1"
          local anchor="$2"
          local new_hash="$3"
          python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); anchor = sys.argv[2]; new_hash = sys.argv[3]; text = path.read_text(); start = text.index(anchor); head, tail = text[:start], text[start:]; tail = re.sub(r"hash = \"sha256-[^\"]+\"", f"hash = \"{new_hash}\"", tail, count=1); path.write_text(head + tail)' "$file" "$anchor" "$new_hash"
        }

        set_attr_hash() {
          local file="$1"
          local attr="$2"
          local new_hash="$3"
          python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); attr = sys.argv[2]; new_hash = sys.argv[3]; text = path.read_text(); text = re.sub(rf"{re.escape(attr)} = \"sha256-[^\"]+\"", f"{attr} = \"{new_hash}\"", text, count=1); path.write_text(text)' "$file" "$attr" "$new_hash"
        }

          refresh_fake_hash_from_build() {
            local file="$1"
            local attr="$2"
            shift 2
            local fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            local output=""
            set_attr_hash "$file" "$attr" "$fake"
            set +e
            output=$("$@" 2>&1)
            local status=$?
            set -e
            local got
            got=$(printf '%s\n' "$output" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | tail -1 || true)
            if [ -z "$got" ]; then
              printf '%s\n' "$output"
              return "$status"
            fi
            set_attr_hash "$file" "$attr" "$got"
            return 0
          }

          update_omniroute_package() {
            local pkg="omniroute"
            local file
            file=$(package_file "$pkg")
            local current_version latest_version npm_hash docs_hash
            current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
            latest_version=$(get_latest_npm_version "$pkg")

            if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
              echo "    Could not determine npm version"
              return 1
            fi

            echo "    Current version: $current_version"
            echo "    Latest version: $latest_version"

            if [ "$current_version" = "$latest_version" ]; then
              echo "    Already up to date"
              return 1
            fi

            npm_hash=$(prefetch_npm_tarball "$pkg" "$latest_version")
            docs_hash=$(prefetch_github "diegosouzapw" "OmniRoute" "v$latest_version")
            if [ -z "$npm_hash" ] || [ -z "$docs_hash" ]; then
              echo "    Could not prefetch npm/docs sources"
              return 1
            fi

            sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
            set_first_hash_after "$file" 'repo = "OmniRoute"' "$docs_hash"
            set_first_hash_after "$file" 'registry.npmjs.org/omniroute' "$npm_hash"
            return 0
          }

          update_cpa_usage_keeper_package() {
            local pkg="cpa-usage-keeper"
            local file
            file=$(package_file "$pkg")
            local current_version latest_tag latest_version src_hash
            current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
            latest_tag=$(get_latest_release "Willxup" "cpa-usage-keeper")
            latest_version="''${latest_tag#v}"
            latest_version="''${latest_version#V}"

            if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
              echo "    Could not determine GitHub release version"
              return 1
            fi

            echo "    Current version: $current_version"
            echo "    Latest version: $latest_version"

            if [ "$current_version" = "$latest_version" ]; then
              echo "    Already up to date"
              return 1
            fi

            src_hash=$(prefetch_github "Willxup" "cpa-usage-keeper" "v$latest_version")
            if [ -z "$src_hash" ]; then
              echo "    Could not prefetch source"
              return 1
            fi

            sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
            set_first_hash_after "$file" 'repo = "cpa-usage-keeper"' "$src_hash"

          echo "    Refreshing npmDepsHash..."
          refresh_fake_hash_from_build "$file" npmDepsHash nix-build -E 'let pkgs = import <nixpkgs> {}; in (pkgs.callPackage ./cpa-usage-keeper.nix {}).web'

          echo "    Refreshing vendorHash..."
          refresh_fake_hash_from_build "$file" vendorHash nix-build -E 'let pkgs = import <nixpkgs> {}; in pkgs.callPackage ./cpa-usage-keeper.nix {}'
          return 0
        }


          update_openchamber_web_package() {
            local pkg="openchamber-web"
            local file
            file=$(package_file "$pkg")
            local current_version latest_tag latest_version src_hash

            current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
            latest_tag=$(get_latest_release "openchamber" "openchamber")
            latest_version="''${latest_tag#v}"
            latest_version="''${latest_version#V}"

            if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
              echo "    Could not determine OpenChamber release version"
              return 1
            fi

            echo "    Current version: $current_version"
            echo "    Latest version: $latest_version"

            if [ "$current_version" = "$latest_version" ]; then
              echo "    Already up to date"
              return 1
            fi

            src_hash=$(prefetch_github "openchamber" "openchamber" "v$latest_version")
            if [ -z "$src_hash" ]; then
              echo "    Could not prefetch OpenChamber source"
              return 1
            fi

            sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
            set_first_hash_after "$file" 'repo = "openchamber"' "$src_hash"

            echo "    Refreshing fixed-output hash..."
            refresh_fake_hash_from_build "$file" outputHash nix-build -E 'let unstable = import <nixpkgs-unstable> {}; in unstable.callPackage ./openchamber-web.nix {}'
            return 0
          }

          update_acp_chat_package() {
            local pkg="acp-chat"
            local file
            file=$(package_file "$pkg")

            echo "  Checking latest ACP UI release..."
            local current_version latest_tag latest_version src_hash
            current_version=$(extract_nix_value "$file" 'version = "\K[^"]+')
            latest_tag=$(get_latest_release "formulahendry" "acp-ui")
            latest_version="''${latest_tag#v}"

            if [ -z "$current_version" ] || [ -z "$latest_tag" ] || [ -z "$latest_version" ]; then
              echo "    Could not determine ACP UI version"
              return 1
            fi

            if [ "$current_version" = "$latest_version" ]; then
              echo "    Already up to date"
              return 1
            fi

            src_hash=$(prefetch_github "formulahendry" "acp-ui" "$latest_tag")
            if [ -z "$src_hash" ]; then
              echo "    Could not prefetch ACP UI source"
              return 1
            fi

            sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
            set_first_hash_after "$file" 'repo = "acp-ui"' "$src_hash"

            echo "    Refreshing npmDepsHash..."
            refresh_fake_hash_from_build "$file" npmDepsHash nix-build -E 'let unstable = import <nixpkgs-unstable> {}; in unstable.callPackage ./acp-chat.nix {}'
            return 0
          }

          select_update_packages

          notify "Scanning for packages..."

          # Dynamically find all .nix files (excluding utility scripts)
          mapfile -t FILES < <(find . -maxdepth 1 -name "*.nix" -not -name "update-pkgs.nix" -not -name "packages.nix" -printf "%f\n" | sort)

          if [ ''${#FILES[@]} -eq 0 ]; then
            notify "No packages found to update."
            exit 0
          fi

          PACKAGES=()
          for file in "''${FILES[@]}"; do
            pkg="''${file%.nix}"
            if contains_package "$pkg" "''${SELECTED_PACKAGES[@]}"; then
              PACKAGES+=("$pkg")
            fi
          done

          if [ ''${#PACKAGES[@]} -eq 0 ]; then
            notify "No packages from '$SELECTED_LABEL' exist in $TARGET."
            exit 0
          fi

    # Create a temporary expression to expose packages for nix-update
    {
      printf '%s\n' '{ pkgs ? import <nixpkgs> {}, unstable ? import <nixpkgs-unstable> {} }:'
      printf '%s\n' '{'
      for pkg in "''${PACKAGES[@]}"; do
          if [[ "$pkg" == "acp-chat" || "$pkg" == "cliproxyapi" || "$pkg" == "omniroute" || "$pkg" == "openchamber-web" ]]; then
            # Edge AI/web packages intentionally build from nixpkgs-unstable so
            # fast-moving Go/Bun/Node dependencies follow upstream APIs. Keep this
            # in sync with modules/custom-packages.nix.
            echo " $pkg = unstable.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "brave-origin" ]; then
            # Supported via custom updater because Brave Origin versions are valid
            # only when the expected prerelease .deb exists and all platform hashes
            # are refreshed together. Source: modules/_pkgs/brave-origin/update.sh
            # and upstream WitteShadovv/nixpkgs pkgs/by-name/br/brave-origin.
            echo " $pkg = pkgs.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "cake-wallet-flatpak" ]; then
            # Supported: versioned GitHub release asset for upstream Flatpak bundle
            echo " $pkg = pkgs.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "limux" ]; then
            # Supported: versioned GitHub tarball release asset from am-will/limux.
            echo " $pkg = unstable.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "antigravity-manager" ]; then
            # Skip: RPM-wrapped AppImage with versioned URL pattern (manual update required)
            echo " # $pkg = (pkgs.callPackage ./$pkg.nix {}).unwrapped; # skipped - RPM-wrapped, versioned URL (manual update)"
          elif [ "$pkg" == "aptos-fonts" ]; then
            # Skip: Static font package from Microsoft CDN (manual update required)
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - static font CDN URL (manual update)"
          elif [ "$pkg" == "iloader" ]; then
            # Skip: iOS device management AppImage with manual download (manual update required)
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - iOS AppImage with manual download (manual update)"
          elif [ "$pkg" == "playwright-cli" ]; then
            # Skip: NPM-based package with Playwright browser bundle dependencies
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - NPM package with browser bundles (manual update)"
          elif [ "$pkg" == "patchright" ]; then
            # Skip: npm package whose CLI and patchright-core versions must stay in
            # lockstep; nix-update can miss npmDepsHash and driver-version coupling.
            # Source: modules/_pkgs/patchright.nix and https://registry.npmjs.org/patchright/latest.
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - NPM package with coupled patchright-core dependency (manual update)"
      elif [ "$pkg" == "omniroute" ]; then
        # Supported via custom updater because the npm tarball and GitHub docs
        # source must move together. Native better-sqlite3 remains pinned until
        # upstream's npm dependency range changes.
        echo " $pkg = unstable.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "cpa-usage-keeper" ]; then
        # Supported via custom updater because src, npmDepsHash, and vendorHash
        # must be refreshed together.
        echo " $pkg = unstable.callPackage ./$pkg.nix {};"
      elif [ "$pkg" == "openchamber-web" ]; then
        # Supported via custom updater because source hash and fixed-output Bun
        # dependency/build hash must be refreshed together.
        echo " $pkg = pkgs.callPackage ./$pkg.nix {};"
          elif [ "$pkg" == "services-auth-gateway" ]; then
            # Skip: local generated Python app with no upstream source URL for nix-update.
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - local generated Python app"
          elif [ "$pkg" == "quickshell-docs-markdown" ]; then
            # Skip: Multi-source Rust package with pinned git deps (manual update required)
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - multi-source Rust with pinned deps (manual update)"
          elif [ "$pkg" == "sideloader" ]; then
            # Skip: iOS sideloading tool with manual download and signing requirements
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - iOS sideloader with signing deps (manual update)"
          elif [ "$pkg" == "snitch" ]; then
            # Skip: TUI network inspector with custom build process
            echo " # $pkg = pkgs.callPackage ./$pkg.nix {}; # skipped - custom build process (manual update)"
          else
            echo " $pkg = pkgs.callPackage ./$pkg.nix {};"
          fi
      done
      printf '%s\n' '}'
    } > packages.nix

          # Set NIX_PATH so the generated packages.nix can resolve the stable set
          # and the real unstable set used by Go packages that need newer toolchains.
          export NIX_PATH=nixpkgs=${pkgs.path}:nixpkgs-unstable=${pkgs.unstable.path}

          notify "Updating ''${#PACKAGES[@]} packages..."

          UPDATED=()
          FAILED=()
          SKIPPED=()

          for pkg in "''${PACKAGES[@]}"; do
            echo "================================================================"
            echo "Checking $pkg..."
            
        # Per-package update strategies
        case "$pkg" in
        "brave-origin")
          # Custom updater selects the latest prerelease only when the expected
          # brave-origin-nightly_<version>_amd64.deb asset exists, then rewrites
          # platform hashes as one matrix. Source: modules/_pkgs/brave-origin/update.sh
          # and upstream WitteShadovv/nixpkgs pkgs/by-name/br/brave-origin/update.sh.
          set +e
          if ./brave-origin/update.sh; then
            UPDATED+=("$pkg")
          else
            FAILED+=("$pkg")
          fi
          set -e
          ;;

        "acp-chat")
          # ACP UI builds from the upstream web lockfile; refresh source and npm cache together.
          if update_acp_chat_package; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "aptos-fonts")
          # Skip: static font CDN URL (manual update required)
          echo " Skipping aptos-fonts (manual update required - static font CDN)"
          SKIPPED+=("$pkg")
          ;;

        "antigravity-manager")
          # Skip: RPM-wrapped AppImage with versioned URL pattern (manual update required)
          echo " Skipping antigravity-manager (manual update required - RPM-wrapped AppImage)"
          SKIPPED+=("$pkg")
          ;;

        "dogecoin")
          # Has versioned URL from GitHub releases
          if update_versioned_url_package "$pkg" "dogecoin" "dogecoin"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "cake-wallet-flatpak")
          # Upstream publishes a versioned Flatpak bundle on GitHub releases.
          if update_versioned_url_package "$pkg" "cake-tech" "cake_wallet"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "limux")
          # Upstream publishes a versioned Linux tarball on GitHub releases.
          if update_versioned_url_package "$pkg" "am-will" "limux"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "openchamber-web")
          # OpenChamber builds from the upstream Bun workspace lock. Keep the
          # release source hash and fixed-output dependency/build hash in sync.
          if update_openchamber_web_package; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "iloader")
          # Skip: iOS AppImage with manual download (manual update required)
          echo " Skipping iloader (manual update required - iOS AppImage with manual download)"
          SKIPPED+=("$pkg")
          ;;

        "playwright-cli")
          # Skip: NPM-based package with browser bundle dependencies (manual update required)
          echo " Skipping playwright-cli (manual update required - NPM with browser bundles)"
          SKIPPED+=("$pkg")
          ;;

        "patchright")
          # Skip: npm package whose CLI and patchright-core versions must stay in
          # lockstep; npm releases can also lead GitHub driver releases, so version
          # discovery needs manual validation before refreshing hashes.
          # Source: modules/_pkgs/patchright.nix and https://registry.npmjs.org/patchright/latest.
          echo " Skipping patchright (manual update required - NPM with coupled patchright-core dependency)"
          SKIPPED+=("$pkg")
          ;;

    "omniroute")
      # Custom updater keeps the npm CLI artifact and GitHub docs source in
      # lockstep, then the normal build serves as the native-module smoke test.
      if update_omniroute_package; then
        if nix-build -E 'let unstable = import <nixpkgs-unstable> {}; in unstable.callPackage ./omniroute.nix {}' >/dev/null; then
          UPDATED+=("$pkg")
        else
          FAILED+=("$pkg")
        fi
      else
        SKIPPED+=("$pkg")
      fi
      ;;

    "cpa-usage-keeper")
      # Custom updater refreshes GitHub source, npmDepsHash, and vendorHash as
      # one coordinated set.
      if update_cpa_usage_keeper_package; then
        UPDATED+=("$pkg")
      else
        SKIPPED+=("$pkg")
      fi
      ;;


        "services-auth-gateway")
          # Skip: local generated Python application with no upstream source URL,
          # so nix-update cannot discover a version or src hash for it.
          echo " Skipping services-auth-gateway (local generated Python app - no upstream source)"
          SKIPPED+=("$pkg")
          ;;

        "quickshell-docs-markdown")
          # Skip: multi-source Rust with pinned git deps (manual update required)
          echo " Skipping quickshell-docs-markdown (manual update required - multi-source Rust)"
          SKIPPED+=("$pkg")
          ;;

        "sideloader")
          # Skip: iOS sideloader with signing deps (manual update required)
          echo " Skipping sideloader (manual update required - iOS sideloader with signing deps)"
          SKIPPED+=("$pkg")
          ;;

        "snitch")
          # Skip: TUI network inspector with custom build process (manual update required)
          echo " Skipping snitch (manual update required - custom build process)"
          SKIPPED+=("$pkg")
          ;;

              "daisyui-mcp"|"mattpocock-skills"|"waydroid-script"|"waydroid-total-spoof")
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

              "niri-screen-time"|"cliproxyapi")
                # Go packages with vendorHash work well with nix-update.
                set +e
                if nix-update -f packages.nix "$pkg"; then
                  UPDATED+=("$pkg")
                else
                  FAILED+=("$pkg")
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
