{ pkgs, ... }:
let
  unstablePath = if pkgs ? unstable then pkgs.unstable.path else pkgs.path;
in
pkgs.writeShellApplication {
  name = "update-pkgs";
  runtimeInputs = [
    pkgs.nix-update
    pkgs.git
    pkgs.libnotify
    pkgs.findutils
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
    pkgs.gnused
    pkgs.nix
    pkgs.nix-prefetch-github
    pkgs.python3
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

    set_label() {
      case "$1" in
      light) printf '%s\n' "Important + light" ;;
      medium) printf '%s\n' "Important + medium" ;;
      heavy) printf '%s\n' "Heavy + less important" ;;
      all) printf '%s\n' "All packages" ;;
      *) printf '%s\n' "Unlisted" ;;
      esac
    }

    set_order() {
      case "$1" in
      light) printf '%s\n' 10 ;;
      medium) printf '%s\n' 20 ;;
      heavy) printf '%s\n' 30 ;;
      *) printf '%s\n' 90 ;;
      esac
    }

    package_set() {
      case "$1" in
      acp-chat | omniroute | omp-desktop | openchamber-web | cpa-usage-keeper | services-auth-gateway | niri-screen-time | daisyui-mcp | lyricsctl | mattpocock-skills)
        printf '%s\n' light
        ;;
      cliproxyapi | brave-origin | patchright | iloader | playwright-cli | cake-wallet-flatpak | orca | limux | seance | dogecoin | antigravity-manager | waydroid-script | waydroid-total-spoof | sideloader | snitch | quickshell-docs-markdown | stdio-to-ws)
        printf '%s\n' medium
        ;;
      wallpapers | aptos-fonts)
        printf '%s\n' heavy
        ;;
      *) printf '%s\n' unlisted ;;
      esac
    }

    package_update_mode() {
      case "$1" in
      acp-chat | cpa-usage-keeper | limux | omniroute | omp-desktop | openchamber-web | orca | seance)
        printf '%s\n' custom
        ;;
      brave-origin)
        printf '%s\n' updater-script
        ;;
      daisyui-mcp | mattpocock-skills | waydroid-script | waydroid-total-spoof)
        printf '%s\n' nix-update-branch
        ;;
      cliproxyapi | niri-screen-time)
        printf '%s\n' nix-update
        ;;
      antigravity-manager | aptos-fonts | iloader | lyricsctl | pass-credential | patchright | playwright-cli | quickshell-docs-markdown | services-auth-gateway | sideloader | snitch | wallpapers)
        printf '%s\n' manual
        ;;
      *) printf '%s\n' nix-update+fallback ;;
      esac
    }

    manual_update_reason() {
      case "$1" in
      antigravity-manager) printf '%s\n' "RPM-wrapped AppImage with versioned URL" ;;
      aptos-fonts) printf '%s\n' "static font CDN URL" ;;
      iloader) printf '%s\n' "iOS AppImage with manual download" ;;
      lyricsctl) printf '%s\n' "repo-local Bun script packaged from this flake" ;;
      pass-credential) printf '%s\n' "repo-local shell parser packaged from this flake" ;;
      patchright) printf '%s\n' "NPM CLI must stay in lockstep with patchright-core" ;;
      playwright-cli) printf '%s\n' "NPM package with browser bundles" ;;
      quickshell-docs-markdown) printf '%s\n' "multi-source Rust with pinned deps" ;;
      services-auth-gateway) printf '%s\n' "local generated Python app" ;;
      sideloader) printf '%s\n' "iOS sideloader with signing deps" ;;
      snitch) printf '%s\n' "custom build process" ;;
      wallpapers) printf '%s\n' "pinned image set with many fixed URLs" ;;
      *) return 1 ;;
      esac
    }

    package_call_expr() {
      local pkg="$1"
      case "$pkg" in
      acp-chat | cliproxyapi | omniroute | openchamber-web)
        printf '%s\n' "unstable.callPackage ./$pkg.nix {}"
        ;;
      limux)
        printf '%s\n' "unstable.callPackage ./limux.nix { pkgs = unstable; }"
        ;;
      *)
        printf '%s\n' "pkgs.callPackage ./$pkg.nix {}"
        ;;
      esac
    }

    package_file_names() {
      find . -maxdepth 1 -name "*.nix" -not -name "update-pkgs.nix" -not -name "packages.nix" -printf "%f\n" | sort
    }

    package_names() {
      package_file_names | sed 's/\.nix$//'
    }

    package_names_by_set() {
      local wanted="$1" pkg
      if [ "$wanted" = all ]; then
        package_names
        return
      fi
      while IFS= read -r pkg; do
        if [ "$(package_set "$pkg")" = "$wanted" ]; then
          printf '%s\n' "$pkg"
        fi
      done < <(package_names)
    }

    package_count_by_set() {
      package_names_by_set "$1" | wc -l | tr -d ' '
    }

    usage() {
      printf '%s\n' \
        "Usage:" \
        "  update-pkgs                         Open TUI menu; non-interactive defaults to update --set light" \
        "  update-pkgs [PACKAGE ...]           Back-compat alias for: update-pkgs update PACKAGE ..." \
        "  update-pkgs update [PACKAGE ...]    Update selected package files" \
        "  update-pkgs update --set SET        Update package set: light, medium, heavy, all" \
        "  update-pkgs test PACKAGE ...        Build flake package and run a safe smoke command" \
        "  update-pkgs test --set SET          Test package set: light, medium, heavy, all" \
        "  update-pkgs revert --yes PACKAGE ..." \
        "                                      Restore selected package files from git HEAD" \
        "  update-pkgs list [--all]            List package sets and package files" \
        "  update-pkgs menu                    Open the interactive TUI" \
        "" \
        "Examples:" \
        "  update-pkgs update omniroute" \
        "  update-pkgs update --set light" \
        "  update-pkgs test limux" \
        "  update-pkgs revert --yes omniroute limux"
    }

    show_intro_once() {
      if [ "''${INTRO_SHOWN:-false}" = true ]; then
        return
      fi
      INTRO_SHOWN=true
      show_update_menu_intro
    }

    render_set_table() {
      local set key pkg packages mode manual buildable total
      {
        printf '%s\n' "Set,Packages,Updater,Notes"
        for key in light medium heavy; do
          packages=""
          manual=0
          buildable=0
          total=0
          while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            total=$((total + 1))
            mode=$(package_update_mode "$pkg")
            [ "$mode" = manual ] && manual=$((manual + 1)) || buildable=$((buildable + 1))
            if [ -z "$packages" ]; then
              packages="$pkg"
            else
              packages="$packages · $pkg"
            fi
          done < <(package_names_by_set "$key")
          set="$(set_label "$key")"
          [ "$key" = light ] && set="$set (default)"
          printf '%s\n' "$set,$total,$buildable auto / $manual manual,$packages"
        done
      } | gum table \
        --print \
        --separator ',' \
        --widths 28,10,18,94 \
        --border rounded \
        --border.foreground 63 \
        --header.foreground 81 \
        --cell.foreground 252 \
        --padding "0 1"
    }

    show_update_menu_intro() {
      gum style \
        --border rounded \
        --border-foreground 63 \
        --padding "1 2" \
        --margin "1 0" \
        --foreground 81 \
        --bold \
        "update-pkgs" \
        "Update, test, or revert custom package entries." \
        "No input for 5 seconds selects update Important + light."

      render_set_table
      echo ""
    }

    select_update_packages() {
      if [ "$#" -gt 0 ]; then
        if [ "''${1:-}" = "--set" ]; then
          if [ "$#" -ne 2 ]; then
            echo "Error: update --set requires exactly one set name." >&2
            exit 2
          fi
          select_set "$2"
          return
        fi
        SELECTED_LABEL="explicit package arguments"
        SELECTED_PACKAGES=("$@")
        return
      fi

      local choice=""
      local status=0

      if [ ! -t 0 ]; then
        select_set light
        return
      fi

      show_intro_once

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
        "Heavy + less important" \
        "All packages" \
        "Pick packages")
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
      "Important + light" | "")
        select_set light
        ;;
      "Important + medium")
        select_set medium
        ;;
      "Heavy + less important")
        select_set heavy
        ;;
      "All packages")
        select_set all
        ;;
      "Pick packages")
        SELECTED_LABEL="manually selected packages"
        choose_explicit_packages "Packages to update"
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

    validate_package_name() {
      case "$1" in
      "" | *[!a-zA-Z0-9._+-]*)
        echo "Error: invalid package name: $1" >&2
        exit 2
        ;;
      esac
    }

    require_package_file() {
      local pkg="$1"
      validate_package_name "$pkg"
      if [ ! -f "$(package_file "$pkg")" ]; then
        echo "Error: unknown package $pkg (expected $(package_file "$pkg"))." >&2
        exit 2
      fi
    }

    package_build_expr() {
      local pkg="$1"
      printf '%s\n' "let pkgs = import <nixpkgs> { config.allowUnfree = true; }; unstable = import <nixpkgs-unstable> { config.allowUnfree = true; }; in $(package_call_expr "$pkg")"
    }

    run_package_build() {
      local pkg="$1"
      nix-build -E "$(package_build_expr "$pkg")"
    }

    build_package_quiet() {
      local pkg="$1"
      run_package_build "$pkg" >/dev/null
    }

    run_nix_update() {
      local pkg="$1"
      shift
      local file before after
      file=$(package_file "$pkg")
      before=$(sha256sum "$file")
      if ! nix-update -f packages.nix "$pkg" "$@"; then
        return 1
      fi
      after=$(sha256sum "$file")
      [ "$before" != "$after" ]
    }

    refresh_package_hash_from_build() {
      local pkg="$1" file="$2" attr="$3"
      refresh_fake_hash_from_build "$file" "$attr" nix-build -E "$(package_build_expr "$pkg")"
    }

    package_smoke_commands() {
      local pkg="$1" bin="$2"
      case "$pkg" in
      acp-chat | cliproxyapi | cpa-usage-keeper | dogecoin | limux | lyricsctl | niri-screen-time | omniroute | openchamber-web | pass-credential | patchright | playwright-cli | seance | services-auth-gateway | sideloader | snitch | stdio-to-ws | waydroid-script | waydroid-total-spoof)
        printf '%s\t%s\n' "$bin" "--help"
        ;;
      *)
        return 0
        ;;
      esac
    }

    run_smoke_command() {
      local cmd="$1" arg="$2"
      if timeout 20s "$cmd" "$arg" </dev/null >/dev/null; then
        echo "  Smoke command passed: $cmd $arg"
        return 0
      fi
      return 1
    }

    run_package_test() {
      local pkg="$1" result main_program bin candidate cmd arg
      require_package_file "$pkg"
      echo "================================================================"
      echo "Testing $pkg..."
      if ! result=$(run_package_build "$pkg"); then
        echo "  Build failed for $pkg."
        FAILED+=("$pkg")
        return 1
      fi
      echo "  Build result: $result"

      if [ "$pkg" = "orca" ]; then
        # The flake main program intentionally launches the Electron GUI, so
        # smoke the packaged CLI entrypoint that Orca itself installs in
        # resources/bin. This still exercises the patched Electron-as-Node runtime.
        if run_smoke_command "$result/opt/Orca/resources/bin/orca-ide" --help; then
          TESTED+=("$pkg")
          return 0
        fi
        echo "  Build passed, but Orca CLI smoke command failed."
        FAILED+=("$pkg")
        return 1
      fi

      main_program=$(nix eval --raw --expr "let p = $(package_build_expr "$pkg"); in p.meta.mainProgram or \"\"" 2>/dev/null || true)
      if [ -n "$main_program" ] && [ -x "$result/bin/$main_program" ]; then
        bin="$result/bin/$main_program"
      else
        bin=""
        for candidate in "$result"/bin/*; do
          [ -x "$candidate" ] || continue
          bin="$candidate"
          break
        done
      fi

      if [ -z "$bin" ]; then
        echo "  No executable found under $result/bin; build validation only."
        TESTED+=("$pkg")
        return 0
      fi

      if [ -z "$(package_smoke_commands "$pkg" "$bin")" ]; then
        echo "  Build validation only; no non-GUI smoke command is configured for $pkg."
        TESTED+=("$pkg")
        return 0
      fi

      while IFS=$'\t' read -r cmd arg; do
        if run_smoke_command "$cmd" "$arg"; then
          TESTED+=("$pkg")
          return 0
        fi
      done < <(package_smoke_commands "$pkg" "$bin")

      echo "  Build passed, but no safe help/version smoke command succeeded for $bin."
      FAILED+=("$pkg")
      return 1
    }

    select_set() {
      local set_name="$1"
      case "$set_name" in
      light | important-light | default)
        SELECTED_LABEL="$(set_label light)"
        mapfile -t SELECTED_PACKAGES < <(package_names_by_set light)
        ;;
      medium | important-medium)
        SELECTED_LABEL="$(set_label medium)"
        mapfile -t SELECTED_PACKAGES < <(package_names_by_set medium)
        ;;
      heavy | less-important)
        SELECTED_LABEL="$(set_label heavy)"
        mapfile -t SELECTED_PACKAGES < <(package_names_by_set heavy)
        ;;
      all)
        SELECTED_LABEL="$(set_label all)"
        mapfile -t SELECTED_PACKAGES < <(package_names_by_set all)
        ;;
      *)
        echo "Error: unknown set $set_name (expected light, medium, heavy, all)." >&2
        exit 2
        ;;
      esac
    }

    choose_explicit_packages() {
      local header="$1"
      mapfile -t SELECTED_PACKAGES < <(package_names | gum choose --no-limit --header "$header" --height 20 --cursor "➜ " --cursor.foreground 212 --header.foreground 63 --selected.foreground 212)
      if [ ''${#SELECTED_PACKAGES[@]} -eq 0 ]; then
        gum style --foreground 196 "No packages selected."
        exit 1
      fi
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

    get_github_release_version() {
      local owner="$1"
      local repo="$2"
      local tag version
      tag=$(get_latest_release "$owner" "$repo")
      version="''${tag#v}"
      version="''${version#V}"
      printf '%s\n' "$version"
    }

    get_npm_package_version() {
      local package="$1"
      local version="$2"
      curl -fs "https://registry.npmjs.org/$package/$version" 2>/dev/null | jq -r '.version // empty' || true
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

    prefetch_github_submodules() {
      local owner="$1"
      local repo="$2"
      local rev="$3"
      nix-prefetch-github "$owner" "$repo" --rev "$rev" --fetch-submodules 2>/dev/null | jq -r '.hash // .sha256 // empty'
    }

    # Function to prefetch URL and get hash
    prefetch_url() {
      local url="$1"
      nix-prefetch-url "$url" 2>/dev/null | xargs nix-hash --type sha256 --to-sri 2>/dev/null || echo ""
    }

    prefetch_url_unpack() {
      local url="$1"
      nix-prefetch-url --unpack "$url" 2>/dev/null | tail -1 | xargs nix-hash --type sha256 --to-sri 2>/dev/null || echo ""
    }

    prefetch_npm_tarball() {
      local package="$1"
      local version="$2"
      prefetch_url "https://registry.npmjs.org/$package/-/$package-$version.tgz"
    }

    get_tag_commit() {
      local owner="$1"
      local repo="$2"
      local tag="$3"
      local ref object_sha object_type

      ref=$(curl -s "https://api.github.com/repos/$owner/$repo/git/ref/tags/$tag")
      object_sha=$(printf '%s\n' "$ref" | jq -r '.object.sha // empty')
      object_type=$(printf '%s\n' "$ref" | jq -r '.object.type // empty')

      if [ -z "$object_sha" ]; then
        return 1
      fi

      if [ "$object_type" = "tag" ]; then
        curl -s "https://api.github.com/repos/$owner/$repo/git/tags/$object_sha" | jq -r '.object.sha // empty'
      else
        printf '%s\n' "$object_sha"
      fi
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
      sources=$(grep -A5 'fetchFromGitHub' "$file" | grep -E 'owner|repo' | paste - - |
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
        done <<<"$sources"
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
        done <<<"$url_sources"
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

    set_first_hash_after() {
      local file="$1"
      local anchor="$2"
      local new_hash="$3"
      python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); anchor = sys.argv[2]; new_hash = sys.argv[3]; text = path.read_text(); start = text.index(anchor); head, tail = text[:start], text[start:]; tail = re.sub(r"hash = \"sha256-[^\"]+\"", f"hash = \"{new_hash}\"", tail, count=1); path.write_text(head + tail)' "$file" "$anchor" "$new_hash"
    }

    first_hash_after() {
      local file="$1"
      local anchor="$2"
      python -c 'import pathlib, re, sys; text = pathlib.Path(sys.argv[1]).read_text(); tail = text[text.index(sys.argv[2]):]; match = re.search(r"hash = \"(sha256-[^\"]+)\"", tail); print(match.group(1) if match else "")' "$file" "$anchor"
    }

    set_attr_hash() {
      local file="$1"
      local attr="$2"
      local new_hash="$3"
      python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); attr = sys.argv[2]; new_hash = sys.argv[3]; text = path.read_text(); text = re.sub(rf"{re.escape(attr)} = \"sha256-[^\"]+\"", f"{attr} = \"{new_hash}\"", text, count=1); path.write_text(text)' "$file" "$attr" "$new_hash"
    }

    attr_hash() {
      local file="$1"
      local attr="$2"
      python -c 'import pathlib, re, sys; text = pathlib.Path(sys.argv[1]).read_text(); match = re.search(rf"{re.escape(sys.argv[2])} = \"(sha256-[^\"]+)\"", text); print(match.group(1) if match else "")' "$file" "$attr"
    }

    is_sri_sha256() {
      case "$1" in
      sha256-????????????????????????????????????????????)
        return 0
        ;;
      *)
        return 1
        ;;
      esac
    }

    update_orca_package() {
      local pkg="orca"
      local file
      file=$(package_file "$pkg")
      local current_version latest_tag latest_version asset_url asset_hash

      current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
      latest_tag=$(get_latest_release "stablyai" "orca")
      latest_version="''${latest_tag#v}"
      latest_version="''${latest_version#V}"

      if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
        echo "    Could not determine Orca release version"
        return 1
      fi

      echo "    Current version: $current_version"
      echo "    Latest version: $latest_version"

      if [ "$current_version" = "$latest_version" ]; then
        echo "    Already up to date"
        return 1
      fi

      asset_url="https://github.com/stablyai/orca/releases/download/v$latest_version/orca-ide_$latest_version"'_amd64.deb'
      echo "    Prefetching Linux .deb: $asset_url"
      asset_hash=$(prefetch_url "$asset_url")
      if [ -z "$asset_hash" ]; then
        echo "    Could not prefetch Orca Linux .deb"
        return 1
      fi

      sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
      set_attr_hash "$file" hash "$asset_hash"
      return 0
    }

    refresh_fake_hash_from_build() {
      local file="$1"
      local attr="$2"
      shift 2
      local fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      local original_hash
      original_hash=$(attr_hash "$file" "$attr")
      if ! is_sri_sha256 "$original_hash"; then
        echo "    Could not find complete $attr before refresh"
        return 1
      fi
      local output=""
      set_attr_hash "$file" "$attr" "$fake"
      set +e
      output=$("$@" 2>&1)
      local status=$?
      set -e
      local got
      got=$(printf '%s\n' "$output" | grep -oP '(got:|got)\s+\Ksha256-[A-Za-z0-9+/=]{44}' | tail -1 || true)
      if ! is_sri_sha256 "$got"; then
        set_attr_hash "$file" "$attr" "$original_hash"
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
      local current_version latest_version npm_version release_version npm_hash docs_hash before_update after_update
      before_update=$(sha256sum "$file")
      current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
      npm_version=$(get_latest_npm_version "$pkg")
      release_version=$(get_github_release_version "diegosouzapw" "OmniRoute")
      latest_version="''${release_version:-$npm_version}"

      if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
        echo "    Could not determine OmniRoute version"
        return 1
      fi

      echo "    Current version: $current_version"
      echo "    Latest GitHub release: ''${release_version:-unknown}"
      echo "    Latest npm artifact: ''${npm_version:-unknown}"

      if [ "$(get_npm_package_version "$pkg" "$latest_version")" != "$latest_version" ]; then
        if [ -n "$npm_version" ] && [ "$(get_npm_package_version "$pkg" "$npm_version")" = "$npm_version" ]; then
          echo "    GitHub release $latest_version is available, but npm has not published omniroute@$latest_version yet"
          echo "    Falling back to npm artifact $npm_version"
          latest_version="$npm_version"
        else
          echo "    GitHub release $latest_version is available, but npm has not published omniroute@$latest_version yet"
          echo "    Skipping: this package builds from the npm CLI tarball, not raw GitHub source"
          return 1
        fi
      fi

      npm_hash=$(prefetch_npm_tarball "$pkg" "$latest_version")
      docs_hash=$(prefetch_github "diegosouzapw" "OmniRoute" "v$latest_version")
      if [ -z "$npm_hash" ] || [ -z "$docs_hash" ]; then
        echo "    Could not prefetch npm/docs sources"
        return 1
      fi

      if [ "$current_version" != "$latest_version" ]; then
        echo "    Updating version: $current_version -> $latest_version"
        sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
      else
        echo "    Version unchanged; refreshing source and npm dependency hashes"
      fi

      set_first_hash_after "$file" 'repo = "OmniRoute"' "$docs_hash"
      set_first_hash_after "$file" 'registry.npmjs.org/omniroute' "$npm_hash"

      echo "    Refreshing npmDepsHash..."
      if refresh_package_hash_from_build "$pkg" "$file" npmDepsHash; then
        :
      else
        return 1
      fi

      after_update=$(sha256sum "$file")
      if [ "$before_update" = "$after_update" ]; then
        echo "    Already up to date"
        return 1
      fi

      return 0
    }

    update_cpa_usage_keeper_package() {
      local pkg="cpa-usage-keeper"
      local file
      file=$(package_file "$pkg")
      local current_version latest_tag latest_version src_hash before_update after_update
      before_update=$(sha256sum "$file")
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

      src_hash=$(prefetch_github "Willxup" "cpa-usage-keeper" "v$latest_version")
      if [ -z "$src_hash" ]; then
        echo "    Could not prefetch source"
        return 1
      fi

      if [ "$current_version" != "$latest_version" ]; then
        echo "    Updating version: $current_version -> $latest_version"
        sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
      else
        echo "    Version unchanged; refreshing source and dependency hashes"
      fi
      set_first_hash_after "$file" 'repo = "cpa-usage-keeper"' "$src_hash"

      echo "    Refreshing npmDepsHash..."
      if ! refresh_fake_hash_from_build "$file" npmDepsHash nix-build -E 'let pkgs = import <nixpkgs> { config.allowUnfree = true; }; in (pkgs.callPackage ./cpa-usage-keeper.nix {}).web'; then
        return 1
      fi

      echo "    Refreshing vendorHash..."
      if ! refresh_fake_hash_from_build "$file" vendorHash nix-build -E 'let pkgs = import <nixpkgs> { config.allowUnfree = true; }; in pkgs.callPackage ./cpa-usage-keeper.nix {}'; then
        return 1
      fi

      after_update=$(sha256sum "$file")
      if [ "$before_update" = "$after_update" ]; then
        echo "    Already up to date"
        return 1
      fi

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
      refresh_package_hash_from_build "$pkg" "$file" outputHash
      return 0
    }

    update_omp_desktop_package() {
      local pkg="omp-desktop"
      local file
      file=$(package_file "$pkg")
      local current_version latest_tag latest_version src_hash

      current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
      latest_tag=$(get_latest_release "apoc" "omp-desktop")
      latest_version="''${latest_tag#v}"
      latest_version="''${latest_version#V}"

      if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
        echo "    Could not determine OMP Desktop release version"
        return 1
      fi

      echo "    Current version: $current_version"
      echo "    Latest version: $latest_version"

      if [ "$current_version" = "$latest_version" ]; then
        echo "    Already up to date"
        return 1
      fi

      src_hash=$(prefetch_github "apoc" "omp-desktop" "$latest_tag")
      if [ -z "$src_hash" ]; then
        echo "    Could not prefetch OMP Desktop source"
        return 1
      fi

      sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
      set_first_hash_after "$file" 'repo = "omp-desktop"' "$src_hash"

      echo "    Refreshing cargoHash..."
      refresh_package_hash_from_build "$pkg" "$file" cargoHash
      return 0
    }

    update_seance_package() {
      local pkg="seance"
      local file
      file=$(package_file "$pkg")
      local current_version current_revision latest_tag latest_version latest_commit latest_revision url src_hash unpacked_hash

      current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
      current_revision=$(grep -oP 'revision \? "\K[^"]+' "$file" | head -1 || true)
      latest_tag=$(get_latest_release "no1msd" "seance")
      latest_version="''${latest_tag#v}"
      latest_version="''${latest_version#V}"
      latest_commit=$(get_tag_commit "no1msd" "seance" "$latest_tag")
      latest_revision="''${latest_commit:0:7}"

      if [ -z "$current_version" ] || [ -z "$latest_version" ] || [ -z "$latest_revision" ]; then
        echo "    Could not determine Seance release version or tag revision"
        return 1
      fi

      echo "    Current version: $current_version-$current_revision"
      echo "    Latest version: $latest_version-$latest_revision"

      if [ "$current_version" = "$latest_version" ] && [ "$current_revision" = "$latest_revision" ]; then
        echo "    Already up to date"
        return 1
      fi

      url="https://github.com/no1msd/seance/releases/download/v$latest_version/seance-$latest_version-src.tar.gz"
      src_hash=$(prefetch_url "$url")
      unpacked_hash=$(prefetch_url_unpack "$url")

      if [ -z "$src_hash" ] || [ -z "$unpacked_hash" ]; then
        echo "    Could not prefetch Seance source tarball"
        return 1
      fi

      sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
      sed -i "s|revision ? \"$current_revision\"|revision ? \"$latest_revision\"|" "$file"
      set_attr_hash "$file" hash "$src_hash"
      set_attr_hash "$file" unpackedHash "$unpacked_hash"

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
      refresh_package_hash_from_build "$pkg" "$file" npmDepsHash
      return 0
    }

    update_limux_package() {
      local pkg="limux"
      local file
      file=$(package_file "$pkg")
      local current_version latest_tag latest_version src_hash patch_hash current_src_hash current_patch_hash
      local changed=false

      current_version=$(grep -oP 'version = "\K[^"]+' "$file" | head -1 || true)
      latest_tag=$(get_latest_release "am-will" "limux")
      latest_version="''${latest_tag#v}"
      latest_version="''${latest_version#V}"

      if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
        echo "    Could not determine Limux release version"
        return 1
      fi

      echo "    Current version: $current_version"
      echo "    Latest version: $latest_version"

      src_hash=$(prefetch_github_submodules "am-will" "limux" "v$latest_version")
      if [ -z "$src_hash" ]; then
        echo "    Could not prefetch Limux source with submodules"
        return 1
      fi

      current_src_hash=$(first_hash_after "$file" 'repo = "limux"')

      # v0.1.19 carries the upstream fractional-scale GLArea fix until it
      # lands in a release. If the PR changes, update its fixed-output hash
      # and let the build refresh cargoHash against the patched source.
      patch_hash=$(prefetch_url "https://github.com/am-will/limux/pull/83.patch")
      current_patch_hash=$(first_hash_after "$file" 'pull/83.patch' || true)

      if [ "$current_version" != "$latest_version" ]; then
        echo "    Updating version: $current_version -> $latest_version"
        sed -i "s|version = \"$current_version\"|version = \"$latest_version\"|" "$file"
        changed=true
      fi

      if [ -n "$current_src_hash" ] && [ "$current_src_hash" != "$src_hash" ]; then
        echo "    Updating source hash: $current_src_hash -> $src_hash"
        set_first_hash_after "$file" 'repo = "limux"' "$src_hash"
        changed=true
      fi

      if [ -n "$patch_hash" ] && [ -n "$current_patch_hash" ] && [ "$current_patch_hash" != "$patch_hash" ]; then
        echo "    Updating fractional-scale patch hash: $current_patch_hash -> $patch_hash"
        set_first_hash_after "$file" 'pull/83.patch' "$patch_hash"
        changed=true
      fi

      if ! $changed; then
        echo "    Already up to date"
        return 1
      fi

      echo "    Refreshing cargoHash..."
      refresh_package_hash_from_build "$pkg" "$file" cargoHash

      return 0
    }

    write_packages_expression() {
      local pkg
      {
        printf '%s\n' '{ pkgs ? import <nixpkgs> {}, unstable ? import <nixpkgs-unstable> {} }:'
        printf '%s\n' '{'
        for pkg in "''${PACKAGES[@]}"; do
          if [ "$(package_update_mode "$pkg")" = manual ]; then
            echo " # $pkg = $(package_call_expr "$pkg"); # skipped - $(manual_update_reason "$pkg")"
          else
            echo " $pkg = $(package_call_expr "$pkg");"
          fi
        done
        printf '%s\n' '}'
      } >packages.nix
    }

    run_update_command() {
      select_update_packages "$@"
      notify "Scanning for packages..."

      # Dynamically find all .nix files (excluding utility scripts)
      mapfile -t FILES < <(package_file_names)

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

      write_packages_expression

      # Set NIX_PATH so the generated packages.nix can resolve the stable set
      # and the real unstable set used by Go packages that need newer toolchains.
      export NIX_PATH=nixpkgs=${pkgs.path}:nixpkgs-unstable=${unstablePath}

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

        "wallpapers")
          # Skip: pinned curated URL list; each image is intentionally chosen.
          echo " Skipping wallpapers (manual update required - pinned image set)"
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

        "orca")
          # Upstream publishes a versioned Linux .deb; refresh version and
          # fixed-output hash together, then build the wrapped Electron app.
          if update_orca_package; then
            if build_package_quiet "$pkg"; then
              UPDATED+=("$pkg")
            else
              FAILED+=("$pkg")
            fi
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "limux")
          # Custom updater keeps source-with-submodules, carried upstream patch,
          # and cargoHash in sync, then builds as a smoke test.
          if update_limux_package; then
            if build_package_quiet "$pkg"; then
              UPDATED+=("$pkg")
            else
              FAILED+=("$pkg")
            fi
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

        "omp-desktop")
          # OMP Desktop is a Tauri/Rust app; refresh source and cargo vendor hash together.
          if update_omp_desktop_package; then
            if build_package_quiet "$pkg"; then
              UPDATED+=("$pkg")
            else
              FAILED+=("$pkg")
            fi
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "iloader")
          # Skip: iOS AppImage with manual download (manual update required)
          echo " Skipping iloader (manual update required - iOS AppImage with manual download)"
          SKIPPED+=("$pkg")
          ;;

        "lyricsctl")
          # Skip: repo-local Bun script is updated with the flake source tree.
          echo " Skipping lyricsctl (manual update required - repo-local Bun script)"
          SKIPPED+=("$pkg")
          ;;

        "pass-credential")
          # Skip: repo-local shell parser is updated with the flake source tree.
          echo " Skipping pass-credential (manual update required - repo-local shell parser)"
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
            if build_package_quiet "$pkg"; then
              UPDATED+=("$pkg")
            else
              FAILED+=("$pkg")
            fi
          else
            SKIPPED+=("$pkg")
          fi
          ;;

        "seance")
          # Custom updater refreshes version, tag revision, compressed source hash,
          # and unpacked source hash, then builds the package as a smoke test.
          if update_seance_package; then
            if build_package_quiet "$pkg"; then
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

        "daisyui-mcp" | "mattpocock-skills" | "waydroid-script" | "waydroid-total-spoof")
          # Track branches - use nix-update with branch mode
          # These packages pin to latest commit on main/master branch
          set +e
          if run_nix_update "$pkg" --version branch; then
            UPDATED+=("$pkg")
          else
            # Fallback to multi-source updater
            if update_multi_source_package "$pkg"; then
              UPDATED+=("$pkg")
            else
              SKIPPED+=("$pkg")
            fi
          fi
          set -e
          ;;

        "niri-screen-time" | "cliproxyapi")
          # Go packages with vendorHash work well with nix-update.
          set +e
          if run_nix_update "$pkg"; then
            UPDATED+=("$pkg")
          else
            SKIPPED+=("$pkg")
          fi
          set -e
          ;;

        *)
          # Default: try nix-update first, fallback to multi-source
          set +e
          if run_nix_update "$pkg"; then
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
        notify "Failed: $(
          IFS=', '
          echo "''${FAILED[*]}"
        )"
        exit 1
      fi

      if [ ''${#UPDATED[@]} -eq 0 ]; then
        notify "No packages updated."
        exit 0
      fi

      echo "================================================================"
      echo "Changes:"
      git --no-pager diff .

      # Final notification
      MSG="Updated: $(
        IFS=', '
        echo "''${UPDATED[*]}"
      )"
      notify "$MSG"
    }

    run_test_command() {
      if [ "''${1:-}" = "--set" ]; then
        if [ "$#" -ne 2 ]; then
          echo "Error: test --set requires exactly one set name." >&2
          exit 2
        fi
        select_set "$2"
      elif [ "$#" -eq 0 ]; then
        if [ -t 0 ]; then
          choose_explicit_packages "Packages to test"
        else
          echo "Error: test requires at least one package." >&2
          exit 2
        fi
      else
        SELECTED_PACKAGES=("$@")
      fi

      export NIX_PATH=nixpkgs=${pkgs.path}:nixpkgs-unstable=${unstablePath}
      local pkg status=0
      for pkg in "''${SELECTED_PACKAGES[@]}"; do
        if ! run_package_test "$pkg"; then
          status=1
        fi
      done
      exit "$status"
    }

    run_revert_command() {
      local assume_yes=false
      if [ "''${1:-}" = "--yes" ]; then
        assume_yes=true
        shift
      fi
      if [ "$#" -eq 0 ]; then
        if [ -t 0 ]; then
          choose_explicit_packages "Packages to revert to git HEAD"
        else
          echo "Error: revert requires --yes and at least one package in non-interactive mode." >&2
          exit 2
        fi
      else
        SELECTED_PACKAGES=("$@")
      fi

      if [ "$assume_yes" != true ]; then
        gum confirm "Revert selected package file(s) to git HEAD?" || exit 1
      fi

      local pkg file
      for pkg in "''${SELECTED_PACKAGES[@]}"; do
        require_package_file "$pkg"
        file=$(package_file "$pkg")
        git checkout -- "$file"
        REVERTED+=("$pkg")
      done
      printf 'Reverted package files:\n'
      printf '  - %s\n' "''${REVERTED[@]}"
    }

    run_list_command() {
      local set pkg
      for set in light medium heavy; do
        printf '%s:\n' "$(set_label "$set")"
        package_names_by_set "$set" | sed 's/^/  - /'
      done
      if [ "''${1:-}" = "--all" ]; then
        printf 'All package files:\n'
        package_file_names | sed 's/^/  - /'
      fi
    }

    run_menu_command() {
      if [ ! -t 0 ]; then
        run_update_command
        return
      fi
      show_intro_once
      local action
      action=$(gum choose --header "Action" --cursor "➜ " --cursor.foreground 212 --header.foreground 63 --selected.foreground 212 "Update packages" "Test packages" "Revert package files" "List package sets")
      case "$action" in
      "Update packages") run_update_command ;;
      "Test packages") run_test_command ;;
      "Revert package files") run_revert_command ;;
      "List package sets") run_list_command --all ;;
      esac
    }

    main() {
      local command="''${1:-menu}"
      case "$command" in
      -h | --help | help) usage ;;
      menu)
        shift || true
        run_menu_command "$@"
        ;;
      update)
        shift
        run_update_command "$@"
        ;;
      test)
        shift
        run_test_command "$@"
        ;;
      revert)
        shift
        run_revert_command "$@"
        ;;
      list)
        shift
        run_list_command "$@"
        ;;
      *) run_update_command "$@" ;;
      esac
    }

    main "$@"
  '';
}
