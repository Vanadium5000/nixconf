{
  coreutils,
  deadnix,
  git,
  gnugrep,
  lib,
  statix,
  writeShellApplication,
}:
let
  mkAudit =
    {
      name,
      runtimeInputs,
      text,
      description,
    }:
    writeShellApplication {
      inherit name runtimeInputs text;
      meta = {
        inherit description;
        homepage = "https://github.com/Vanadium5000/nixconf";
        license = lib.licenses.gpl3Only;
        mainProgram = name;
        platforms = lib.platforms.linux;
      };
    };
in
{
  persist-audit = mkAudit {
    name = "persist-audit";
    runtimeInputs = [
      coreutils
      gnugrep
    ];
    description = "List Nixconf's effective persistent and cache state paths";
    text = ''
      set -euo pipefail

      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        cat <<'EOF'
      Usage: persist-audit

      Prints the repository's persistence and cache declarations, grouped by
      system/home state and cache tiers. It is read-only and does not inspect or
      modify a live host.
      EOF
        exit 0
      fi

      if [ "$#" -ne 0 ]; then
        echo "persist-audit: unexpected argument: $1" >&2
        exit 64
      fi

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -z "$repo_root" ]; then
        echo "persist-audit: run from a nixconf checkout" >&2
        exit 1
      fi

      cd "$repo_root"
      grep -RInE \
        --include='*.nix' \
        'impermanence\.(nixos|home)(\.cache)?\.(directories|files)|environment\.persistence' \
        modules packages external-packages programmes hosts \
        || true
    '';
  };

  nix-unused-audit = mkAudit {
    name = "nix-unused-audit";
    runtimeInputs = [
      deadnix
      git
      statix
    ];
    description = "Run deadnix and statix against the Nixconf source tree";
    text = ''
      set -euo pipefail

      if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
        cat <<'EOF'
      Usage: nix-unused-audit [--strict]

      Runs deadnix and statix over Nix source directories. The default reports
      findings without failing; --strict returns non-zero if deadnix finds unused
      bindings. The command is read-only.
      EOF
        exit 0
      fi

      strict=false
      case "''${1:-}" in
        "") ;;
        --strict) strict=true ;;
        *)
          echo "nix-unused-audit: unknown argument: $1" >&2
          exit 64
          ;;
      esac

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -z "$repo_root" ]; then
        echo "nix-unused-audit: run from a nixconf checkout" >&2
        exit 1
      fi

      cd "$repo_root"
      if [ "$strict" = true ]; then
        deadnix --fail flake.nix lib packages external-packages programmes modules hosts
      else
        deadnix flake.nix lib packages external-packages programmes modules hosts
      fi
      # Statix has advisory style rules whose value depends on local module
      # conventions. Report them without converting an informational audit into
      # a failing command; deadnix --strict remains the explicit gate.
      statix check . || true
    '';
  };
}
