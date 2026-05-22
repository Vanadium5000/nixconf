set -euo pipefail

git_bin=@git@
gum_bin=@gum@
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
generated_identity_dir="$config_home/git/identities"
manager_dir="$config_home/git/identity-manager"
custom_identity_dir="$manager_dir/identities"
global_rules="$manager_dir/includes.gitconfig"
selected_identity_name=""
selected_identity_source=""
selected_identity_path=""

usage() {
  cat <<'EOF'
usage: git-identity [command] [args]

commands:
  setup [repo]             show current identity and interactively fix/change it
  current [repo]           show effective identity and config origins
  doctor [repo]            fail if a repo has no explicit identity
  use <identity> [repo]    set repo-local identity using an existing identity
  global <identity> [repo] set a persistent global gitdir rule for this repo
  add                      interactively add a mutable identity
  list                     list generated and mutable identities
  manage [repo]            open the full identity manager menu
EOF
}

ensure_manager() {
  mkdir -p "$custom_identity_dir"
  if [ ! -e "$global_rules" ]; then
    {
      printf '# Managed by git-identity. This file is included by ~/.gitconfig.\n'
      printf '%s\n' '# Add includeIf rules here manually or through git-identity global.'
    } >"$global_rules"
  fi
}

repo_arg() {
  if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
  fi

  if [ "$#" -eq 1 ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' .
  fi
}

git_repo_root() {
  local target="$1"
  "$git_bin" -C "$target" rev-parse --show-toplevel 2>/dev/null
}

require_repo_root() {
  local target root
  target="$(repo_arg "$@")"
  root="$(git_repo_root "$target")" || {
    printf 'error: not a git repository: %s\n' "$target" >&2
    return 2
  }
  printf '%s\n' "$root"
}

identity_rows() {
  ensure_manager
  local dir path name source
  for dir in "$generated_identity_dir" "$custom_identity_dir"; do
    if [ "$dir" = "$generated_identity_dir" ]; then
      source="generated"
    else
      source="mutable"
    fi

    for path in "$dir"/*.gitconfig; do
      [ -e "$path" ] || continue
      name="${path##*/}"
      name="${name%.gitconfig}"
      printf '%s\t%s\t%s\n' "$name" "$source" "$path"
    done
  done
}

custom_identity_rows() {
  ensure_manager
  local path name
  for path in "$custom_identity_dir"/*.gitconfig; do
    [ -e "$path" ] || continue
    name="${path##*/}"
    name="${name%.gitconfig}"
    printf '%s\tmutable\t%s\n' "$name" "$path"
  done
}

parse_identity_row() {
  IFS=$'\t' read -r selected_identity_name selected_identity_source selected_identity_path <<<"$1"
}

identity_display() {
  local row name source path git_name git_email
  row="$1"
  IFS=$'\t' read -r name source path <<<"$row"
  git_name="$($git_bin config -f "$path" --get user.name 2>/dev/null || true)"
  git_email="$($git_bin config -f "$path" --get user.email 2>/dev/null || true)"
  printf '%s [%s] — %s <%s>\t%s\n' "$name" "$source" "$git_name" "$git_email" "$row"
}

choose_line() {
  local prompt="$1"
  shift

  if [ "$#" -eq 0 ]; then
    return 1
  fi

  if [ -t 0 ] && [ -t 1 ] && [ -x "$gum_bin" ]; then
    "$gum_bin" choose \
      --header "$prompt" \
      --height 12 \
      --cursor "➜ " \
      --cursor.foreground 212 \
      --header.foreground 63 \
      --item.foreground 246 \
      --selected.foreground 212 \
      "$@"
    return
  fi

  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    return 1
  fi

  local index=1 choice line
  for line in "$@"; do
    printf '%2d) %s\n' "$index" "$line" >/dev/tty
    index=$((index + 1))
  done

  printf '%s' "$prompt" >/dev/tty
  IFS= read -r choice </dev/tty || return 1
  case "$choice" in
    ''|*[!0-9]*) return 1 ;;
  esac

  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$#" ]; then
    return 1
  fi

  index=1
  for line in "$@"; do
    if [ "$index" -eq "$choice" ]; then
      printf '%s\n' "$line"
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

choose_identity() {
  local rows=() display_rows=() row selected selected_display
  mapfile -t rows < <(identity_rows)

  if [ "${#rows[@]}" -eq 0 ]; then
    printf 'No identities exist yet.\n' >&2
    return 1
  fi

  for row in "${rows[@]}"; do
    display_rows+=("$(identity_display "$row")")
  done

  selected_display="$(choose_line 'identity> ' "${display_rows[@]}")" || return 1
  selected="${selected_display##*$'\t'}"
  parse_identity_row "$selected"
}

choose_custom_identity() {
  local rows=() display_rows=() row selected selected_display
  mapfile -t rows < <(custom_identity_rows)

  if [ "${#rows[@]}" -eq 0 ]; then
    printf 'No mutable identities exist yet. Generated identities are managed by Nix.\n' >&2
    return 1
  fi

  for row in "${rows[@]}"; do
    display_rows+=("$(identity_display "$row")")
  done

  selected_display="$(choose_line 'mutable identity> ' "${display_rows[@]}")" || return 1
  selected="${selected_display##*$'\t'}"
  parse_identity_row "$selected"
}

find_identity_by_name() {
  local wanted="$1" row name source path

  while IFS=$'\t' read -r name source path; do
    if [ "$source" = "mutable" ] && [ "$name" = "$wanted" ]; then
      selected_identity_name="$name"
      selected_identity_source="$source"
      selected_identity_path="$path"
      return 0
    fi
  done < <(identity_rows)

  while IFS=$'\t' read -r name source path; do
    if [ "$name" = "$wanted" ]; then
      selected_identity_name="$name"
      selected_identity_source="$source"
      selected_identity_path="$path"
      return 0
    fi
  done < <(identity_rows)

  return 1
}

prompt_value() {
  local label="$1" default="${2:-}" value
  if [ -t 0 ] && [ -t 1 ] && [ -x "$gum_bin" ]; then
    if [ -n "$default" ]; then
      "$gum_bin" input \
        --prompt "$label: " \
        --value "$default" \
        --cursor.foreground 212 \
        --prompt.foreground 63
    else
      "$gum_bin" input \
        --prompt "$label: " \
        --cursor.foreground 212 \
        --prompt.foreground 63
    fi
    return
  fi

  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf 'error: interactive input requires a tty\n' >&2
    return 2
  fi

  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default" >/dev/tty
  else
    printf '%s: ' "$label" >/dev/tty
  fi
  IFS= read -r value </dev/tty || return 2
  printf '%s\n' "${value:-$default}"
}

confirm() {
  local label="$1" answer
  if [ -t 0 ] && [ -t 1 ] && [ -x "$gum_bin" ]; then
    "$gum_bin" confirm \
      --prompt.foreground 63 \
      --selected.foreground 212 \
      --unselected.foreground 246 \
      "$label"
    return
  fi

  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    return 1
  fi
  printf '%s [y/N]: ' "$label" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

add_identity() {
  ensure_manager
  local key name email signing_key gpg_format sign_by_default path

  while true; do
    key="$(prompt_value 'identity key (letters, numbers, dot, dash, underscore)')" || return 2
    case "$key" in
      '') printf 'identity key cannot be empty\n' >&2 ;;
      *[!A-Za-z0-9._-]*) printf 'identity key contains invalid characters\n' >&2 ;;
      *) break ;;
    esac
  done

  if find_identity_by_name "$key"; then
    printf 'error: identity already exists: %s (%s)\n' "$selected_identity_name" "$selected_identity_source" >&2
    return 1
  fi

  name="$(prompt_value 'user.name')" || return 2
  email="$(prompt_value 'user.email')" || return 2
  signing_key="$(prompt_value 'user.signingKey (optional)')" || return 2
  gpg_format=""
  sign_by_default="false"

  if [ -n "$signing_key" ]; then
    gpg_format="$(prompt_value 'gpg.format' 'ssh')" || return 2
    if confirm 'sign commits by default for this identity?'; then
      sign_by_default="true"
    fi
  fi

  path="$custom_identity_dir/$key.gitconfig"
  : >"$path"
  "$git_bin" config -f "$path" user.name "$name"
  "$git_bin" config -f "$path" user.email "$email"
  "$git_bin" config -f "$path" user.useConfigOnly true

  if [ -n "$signing_key" ]; then
    "$git_bin" config -f "$path" user.signingKey "$signing_key"
    "$git_bin" config -f "$path" gpg.format "$gpg_format"
    "$git_bin" config -f "$path" commit.gpgSign "$sign_by_default"
  fi

  printf 'created mutable identity: %s\n' "$path"
  selected_identity_name="$key"
  selected_identity_source="mutable"
  selected_identity_path="$path"
}

show_identities() {
  local row name source path git_name git_email signing_key
  while IFS=$'\t' read -r name source path; do
    git_name="$($git_bin config -f "$path" --get user.name 2>/dev/null || true)"
    git_email="$($git_bin config -f "$path" --get user.email 2>/dev/null || true)"
    signing_key="$($git_bin config -f "$path" --get user.signingKey 2>/dev/null || true)"
    printf '%-20s %-9s %s <%s>' "$name" "$source" "$git_name" "$git_email"
    if [ -n "$signing_key" ]; then
      printf ' signingKey=%s' "$signing_key"
    fi
    printf '\n  %s\n' "$path"
  done < <(identity_rows)
}

identity_origin_label() {
  local root="$1" line origin path base
  line="$($git_bin -C "$root" config --show-origin --get user.email 2>/dev/null || true)"
  [ -n "$line" ] || return 1
  origin="${line%%$'\t'*}"
  case "$origin" in
    file:*)
      path="${origin#file:}"
      base="${path##*/}"
      base="${base%.gitconfig}"
      printf '%s (%s)\n' "$base" "$path"
      ;;
    *)
      printf '%s\n' "$origin"
      ;;
  esac
}

show_summary() {
  local root="$1" name email signing_key origin_label
  name="$($git_bin -C "$root" config --get user.name 2>/dev/null || true)"
  email="$($git_bin -C "$root" config --get user.email 2>/dev/null || true)"
  signing_key="$($git_bin -C "$root" config --get user.signingKey 2>/dev/null || true)"
  origin_label="$(identity_origin_label "$root" || true)"

  printf 'repo:        %s\n' "$root"
  if [ -n "$name" ] && [ -n "$email" ]; then
    printf 'status:      configured\n'
    printf 'identity:    %s\n' "${origin_label:-unknown origin}"
    printf 'name:        %s\n' "$name"
    printf 'email:       %s\n' "$email"
    if [ -n "$signing_key" ]; then
      printf 'signingKey:  %s\n' "$signing_key"
    fi
  else
    printf 'status:      missing identity\n'
    printf 'name:        %s\n' "${name:-<missing>}"
    printf 'email:       %s\n' "${email:-<missing>}"
  fi
}

show_current() {
  local root
  root="$(require_repo_root "$@")" || return $?
  show_summary "$root"
  printf '\norigins:\n'
  "$git_bin" -C "$root" config --show-origin --get-regexp '^(user|commit|gpg)\.' || true
}

repo_identity_config_path() {
  local root="$1" git_dir
  git_dir="$($git_bin -C "$root" rev-parse --absolute-git-dir)"
  printf '%s/nixconf-identity.gitconfig\n' "$git_dir"
}

ensure_repo_identity_include() {
  local root="$1" include_file="$2" existing has_include=0
  while IFS= read -r existing; do
    if [ "$existing" = "$include_file" ]; then
      has_include=1
      break
    fi
  done < <("$git_bin" -C "$root" config --local --get-all include.path 2>/dev/null || true)

  if [ "$has_include" -eq 0 ]; then
    "$git_bin" -C "$root" config --local --add include.path "$include_file"
  fi
}

set_repo_identity_path() {
  local root="$1" identity_path="$2" include_file
  include_file="$(repo_identity_config_path "$root")"
  mkdir -p "${include_file%/*}"
  : >"$include_file"
  "$git_bin" config -f "$include_file" include.path "$identity_path"
  ensure_repo_identity_include "$root" "$include_file"
  printf 'repo-local identity include set: %s -> %s\n' "$include_file" "$identity_path"
}

set_repo_identity() {
  local root="$1"
  choose_identity || return 1
  set_repo_identity_path "$root" "$selected_identity_path"
  show_summary "$root"
}

set_repo_identity_by_name() {
  local identity="$1" root="$2"
  if ! find_identity_by_name "$identity"; then
    printf 'error: unknown identity: %s\n' "$identity" >&2
    printf 'known identities:\n' >&2
    show_identities >&2
    return 2
  fi
  set_repo_identity_path "$root" "$selected_identity_path"
  show_summary "$root"
}

set_global_identity_path() {
  local root="$1" identity_path="$2" condition key
  ensure_manager
  condition="gitdir:${root%/}/"
  key="includeIf.${condition}.path"
  "$git_bin" config -f "$global_rules" --replace-all "$key" "$identity_path"
  printf 'global gitdir rule set in %s\n' "$global_rules"
  printf '%s -> %s\n' "$condition" "$identity_path"
}

set_global_identity() {
  local root="$1"
  choose_identity || return 1
  set_global_identity_path "$root" "$selected_identity_path"
  show_summary "$root"
}

set_global_identity_by_name() {
  local identity="$1" root="$2"
  if ! find_identity_by_name "$identity"; then
    printf 'error: unknown identity: %s\n' "$identity" >&2
    printf 'known identities:\n' >&2
    show_identities >&2
    return 2
  fi
  set_global_identity_path "$root" "$selected_identity_path"
  show_summary "$root"
}

doctor() {
  local root missing=0
  root="$(require_repo_root "$@")" || return $?

  if ! "$git_bin" -C "$root" config --get user.name >/dev/null; then
    printf 'error: user.name is not configured for %s\n' "$root" >&2
    missing=1
  fi

  if ! "$git_bin" -C "$root" config --get user.email >/dev/null; then
    printf 'error: user.email is not configured for %s\n' "$root" >&2
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    printf '%s\n' 'hint: run gid or git-identity setup to choose/create an identity for this repo' >&2
    return 1
  fi

  printf 'ok: %s\n' "$root"
  show_summary "$root"
}

edit_identity() {
  choose_custom_identity || return 1
  "${EDITOR:-vi}" "$selected_identity_path"
}

delete_identity() {
  choose_custom_identity || return 1
  printf 'selected mutable identity: %s (%s)\n' "$selected_identity_name" "$selected_identity_path"
  if confirm 'delete this identity file?'; then
    rm -f "$selected_identity_path"
    printf 'deleted %s\n' "$selected_identity_path"
  fi
}

setup_repo() {
  local root action name email
  root="$(require_repo_root "$@")" || return $?
  show_summary "$root"
  printf '\n'

  name="$($git_bin -C "$root" config --get user.name 2>/dev/null || true)"
  email="$($git_bin -C "$root" config --get user.email 2>/dev/null || true)"

  if [ -z "$name" ] || [ -z "$email" ]; then
    action="$(choose_line 'setup> ' \
      'Set repo-local identity' \
      'Set persistent global rule for this repo path' \
      'Add a new identity, then set it repo-local' \
      'Add a new identity, then set it globally for this repo path' \
      'List identities' \
      'Quit')" || return 1
  else
    action="$(choose_line 'manage> ' \
      'Change repo-local identity' \
      'Set/replace persistent global rule for this repo path' \
      'Add a new identity' \
      'List identities' \
      'Show full origins' \
      'Quit')" || return 1
  fi

  case "$action" in
    'Set repo-local identity'|'Change repo-local identity') set_repo_identity "$root" ;;
    'Set persistent global rule for this repo path'|'Set/replace persistent global rule for this repo path') set_global_identity "$root" ;;
    'Add a new identity, then set it repo-local') add_identity && set_repo_identity_path "$root" "$selected_identity_path" && show_summary "$root" ;;
    'Add a new identity, then set it globally for this repo path') add_identity && set_global_identity_path "$root" "$selected_identity_path" && show_summary "$root" ;;
    'Add a new identity') add_identity ;;
    'List identities') show_identities ;;
    'Show full origins') show_current "$root" ;;
    'Quit') return 0 ;;
  esac
}

manage() {
  local root="" action
  if root="$(git_repo_root "$(repo_arg "$@")")"; then
    :
  else
    root=""
  fi

  while true; do
    if [ -n "$root" ]; then
      show_summary "$root"
      printf '\n'
      action="$(choose_line 'git-identity> ' \
        'Set repo-local identity' \
        'Set persistent global rule for this repo path' \
        'Add identity' \
        'Edit mutable identity' \
        'Delete mutable identity' \
        'List identities' \
        'Show full origins' \
        'Quit')" || return 1
    else
      action="$(choose_line 'git-identity> ' \
        'Add identity' \
        'Edit mutable identity' \
        'Delete mutable identity' \
        'List identities' \
        'Quit')" || return 1
    fi

    case "$action" in
      'Set repo-local identity') set_repo_identity "$root" ;;
      'Set persistent global rule for this repo path') set_global_identity "$root" ;;
      'Add identity') add_identity ;;
      'Edit mutable identity') edit_identity ;;
      'Delete mutable identity') delete_identity ;;
      'List identities') show_identities ;;
      'Show full origins') show_current "$root" ;;
      'Quit') return 0 ;;
    esac
    printf '\n'
  done
}

main() {
  ensure_manager

  if [ "$#" -eq 0 ]; then
    setup_repo
    return
  fi

  local command="$1"
  shift

  case "$command" in
    setup) setup_repo "$@" ;;
    manage) manage "$@" ;;
    current) show_current "$@" ;;
    doctor) doctor "$@" ;;
    list) show_identities ;;
    add) add_identity ;;
    use)
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        printf 'usage: git-identity use <identity> [repo]\n' >&2
        return 2
      fi
      local identity="$1" target="${2:-.}" root
      root="$(git_repo_root "$target")" || {
        printf 'error: not a git repository: %s\n' "$target" >&2
        return 2
      }
      set_repo_identity_by_name "$identity" "$root"
      ;;
    global)
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        printf 'usage: git-identity global <identity> [repo]\n' >&2
        return 2
      fi
      local identity="$1" target="${2:-.}" root
      root="$(git_repo_root "$target")" || {
        printf 'error: not a git repository: %s\n' "$target" >&2
        return 2
      }
      set_global_identity_by_name "$identity" "$root"
      ;;
    -h|--help|help) usage ;;
    *)
      printf 'error: unknown command: %s\n' "$command" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
