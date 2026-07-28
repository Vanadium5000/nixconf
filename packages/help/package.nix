{
  bash,
  coreutils,
  jq,
  less,
  lib,
  writeShellApplication,
}:
writeShellApplication {
  name = "help";
  runtimeInputs = [
    bash
    coreutils
    jq
    less
  ];
  text = ''
    set -euo pipefail

    usage() {
      cat <<'EOF'
    Usage: help [--plain] [--pager] [--docs FILE | --docs-json JSON]

    Render Nixconf commands enabled on this host.

    Options:
      --plain           Disable ANSI formatting; suitable for pipes and logs.
      --pager           View the formatted output in less.
      --docs FILE       Read a command-document JSON file instead of NIXCONF_HELP_DOCS.
      --docs-json JSON  Read a command-document JSON value directly.
      -h, --help        Show this help text.

    Documentation source precedence: --docs-json, --docs, NIXCONF_HELP_DOCS,
    NIXCONF_HELP_DOCS_JSON. Host activation sets NIXCONF_HELP_DOCS to the generated
    /etc/nixconf/help.json file.
    EOF
    }

    plain=0
    pager=0
    docs_file="''${NIXCONF_HELP_DOCS:-}"
    docs_json="''${NIXCONF_HELP_DOCS_JSON:-}"

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --plain)
          plain=1
          ;;
        --pager)
          pager=1
          ;;
        --docs)
          [ "$#" -ge 2 ] || {
            printf 'help: --docs requires a file path\n' >&2
            exit 64
          }
          docs_file="$2"
          docs_json=""
          shift
          ;;
        --docs-json)
          [ "$#" -ge 2 ] || {
            printf 'help: --docs-json requires a JSON value\n' >&2
            exit 64
          }
          docs_json="$2"
          docs_file=""
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          printf 'help: unknown option: %s\n' "$1" >&2
          usage >&2
          exit 64
          ;;
      esac
      shift
    done

    if [ -n "$docs_json" ]; then
      docs_input=$(mktemp)
      trap 'rm -f "$docs_input"' EXIT
      printf '%s\n' "$docs_json" > "$docs_input"
    elif [ -n "$docs_file" ]; then
      docs_input="$docs_file"
    else
      printf 'help: no documentation source; set NIXCONF_HELP_DOCS or pass --docs/--docs-json\n' >&2
      exit 66
    fi

    if [ ! -r "$docs_input" ]; then
      printf 'help: documentation source is not readable: %s\n' "$docs_input" >&2
      exit 66
    fi

    if ! ${jq}/bin/jq -e '
      type == "object"
      and (.version == 1)
      and (.commands | type == "array")
      and all(
        .commands[];
        (.command | type == "string")
        and (.aliases | type == "array" and all(.[]; type == "string"))
        and (.description | type == "string")
        and (.usage | type == "string")
        and (.details | type == "string")
      )
    ' "$docs_input" >/dev/null; then
      printf 'help: invalid documentation source: %s\n' "$docs_input" >&2
      exit 65
    fi

    render_plain() {
      ${jq}/bin/jq -r '
        .commands
        | sort_by(.command)
        | .[]
        | ([.command] + .aliases | join(", ")) as $names
        | "\($names)\n  \(.description)"
          + (if .usage == "" then "" else "\n  Usage: \(.usage)" end)
          + (if .details == "" then "" else "\n  \(.details | gsub("\\n"; "\\n  "))" end)
          + "\n"
      ' "$docs_input"
    }

    render_formatted() {
      ${jq}/bin/jq -r '
        .commands
        | sort_by(.command)
        | .[]
        | ([.command] + .aliases | join(", ")) as $names
        | "\u001b[1;38;5;81m\($names)\u001b[0m\n"
          + "  \(.description)"
          + (if .usage == "" then "" else "\n  \u001b[2mUsage\u001b[0m  \(.usage)" end)
          + (if .details == "" then "" else "\n  \(.details | gsub("\\n"; "\\n  "))" end)
          + "\n"
      ' "$docs_input"
    }

    if [ "$plain" -eq 1 ]; then
      render_plain
    elif [ "$pager" -eq 1 ]; then
      render_formatted | ${less}/bin/less --RAW-CONTROL-CHARS --quit-if-one-screen
    elif [ ! -t 1 ]; then
      render_plain
    else
      printf '\033[1mNixconf commands enabled on this host\033[0m\n\n'
      render_formatted
    fi
  '';
  meta = {
    description = "Render documentation for Nixconf commands enabled on the current host";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "help";
    platforms = lib.platforms.unix;
  };
}
