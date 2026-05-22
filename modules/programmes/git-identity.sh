set -euo pipefail

git_bin=@git@
gum_bin=@gum@
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
manager_dir="$config_home/git/identity-manager"
identity_dir="$manager_dir/identities"
selected_identity_path=""
selected_identity_name=""
selected_identity_email=""

usage() {
  cat <<'EOF'
usage: git-identity [command] [args]

commands:
  setup [repo]          open the identity picker; default command for gi/gid
  manage [repo]         alias for setup
  current [repo]        show the current repo identity
  doctor [repo]         fail if the repo has no effective user.name/user.email
  list                  list saved git-identity user/email pairs
  add [repo]            add a saved pair; optionally use it for the current repo
  use <identity> [repo] set repo-local user.name/user.email from a saved pair
  edit <identity>       edit a saved pair
  delete <identity>     delete a saved pair
EOF
}

ensure_manager() {
  mkdir -p "$identity_dir"
}

has_tui() {
  [ -t 0 ] && [ -t 2 ] && [ -x "$gum_bin" ]
}

require_tui() {
  if ! has_tui; then
    printf 'error: interactive git-identity requires gum and an interactive terminal\n' >&2
    return 2
  fi
}

style() {
  if has_tui; then
    "$gum_bin" style "$@"
  else
    shift $(( $# - 1 ))
    printf '%s\n' "$1"
  fi
}

paint() {
  local color="$1" text="$2"
  if has_tui; then
    "$gum_bin" style --foreground "$color" "$text"
  else
    printf '%s\n' "$text"
  fi
}

paint_bold() {
  local color="$1" text="$2"
  if has_tui; then
    "$gum_bin" style --foreground "$color" --bold "$text"
  else
    printf '%s\n' "$text"
  fi
}

choose_index() {
  local header="$1"
  shift

  require_tui || return $?
  if [ "$#" -eq 0 ]; then
    return 1
  fi

  local selected index
  selected="$(
    "$gum_bin" choose \
      --header "$header" \
      --height 16 \
      --cursor "› " \
      --cursor.foreground 212 \
      --header.foreground 63 \
      --item.foreground 252 \
      --selected.foreground 212 \
      "$@"
  )" || return 1

  index=0
  for option in "$@"; do
    if [ "$option" = "$selected" ]; then
      printf '%s\n' "$index"
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

confirm_default_yes() {
  local prompt="$1"
  require_tui || return $?
  "$gum_bin" confirm \
    --default=true \
    --prompt.foreground 63 \
    --selected.foreground 212 \
    --unselected.foreground 246 \
    "$prompt"
}

repo_arg() {
  if [ "$#" -gt 1 ]; then
    usage >&2
    return 2
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

maybe_repo_root() {
  local target
  target="$(repo_arg "$@")" || return $?
  git_repo_root "$target" || true
}

require_repo_root() {
  local target root
  target="$(repo_arg "$@")" || return $?
  root="$(git_repo_root "$target")" || {
    printf 'error: not a git repository: %s\n' "$target" >&2
    return 2
  }
  printf '%s\n' "$root"
}

identity_path_for_key() {
  printf '%s/%s.gitconfig\n' "$identity_dir" "$1"
}

validate_key() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

identity_rows() {
  ensure_manager
  local path key name email
  for path in "$identity_dir"/*.gitconfig; do
    [ -e "$path" ] || continue
    key="${path##*/}"
    key="${key%.gitconfig}"
    name="$($git_bin config -f "$path" --get user.name 2>/dev/null || true)"
    email="$($git_bin config -f "$path" --get user.email 2>/dev/null || true)"
    [ -n "$name" ] || [ -n "$email" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$key" "$path" "$name" "$email"
  done
}

parse_identity_row() {
  local row="$1"
  row="${row#*$'\t'}"
  IFS=$'\t' read -r selected_identity_path selected_identity_name selected_identity_email <<<"$row"
}

find_identity_by_key() {
  local wanted="$1" key path name email
  while IFS=$'\t' read -r key path name email; do
    if [ "$key" = "$wanted" ]; then
      selected_identity_path="$path"
      selected_identity_name="$name"
      selected_identity_email="$email"
      return 0
    fi
  done < <(identity_rows)
  return 1
}

identity_option() {
  local row key path name email styled_name styled_email styled_key
  row="$1"
  IFS=$'\t' read -r key path name email <<<"$row"

  styled_name="$(paint_bold 212 "${name:-<missing name>}")"
  styled_email="$(paint 86 "<${email:-missing email}>")"
  styled_key="$(paint 246 "$key")"
  printf '%s  %s  %s\n' "$styled_name" "$styled_email" "$styled_key"
}

print_repo_card() {
  local root="$1" name email origin name_origin email_origin body

  if [ -z "$root" ]; then
    body="$(printf 'Repo:  not in a git repository\nMode:  manage saved identities only')"
  else
    name="$($git_bin -C "$root" config --get user.name 2>/dev/null || true)"
    email="$($git_bin -C "$root" config --get user.email 2>/dev/null || true)"
    name_origin="$($git_bin -C "$root" config --show-origin --get user.name 2>/dev/null || true)"
    email_origin="$($git_bin -C "$root" config --show-origin --get user.email 2>/dev/null || true)"
    name_origin="${name_origin%%$'\t'*}"
    email_origin="${email_origin%%$'\t'*}"

    if [ -n "$name_origin" ] && [ "$name_origin" = "$email_origin" ]; then
      origin="${name_origin#file:}"
    elif [ -n "$name_origin" ] || [ -n "$email_origin" ]; then
      origin="mixed git config origins"
    else
      origin="not set"
    fi

    body="$(printf 'Repo:  %s\nName:  %s\nEmail: %s\nFrom:  %s' "$root" "${name:-<missing>}" "${email:-<missing>}" "$origin")"
  fi

  if has_tui; then
    "$gum_bin" style \
      --border rounded \
      --border-foreground 63 \
      --padding '0 1' \
      --margin '0 0 1 0' \
      "$body"
  else
    printf '%s\n' "$body"
  fi
}

print_identity_list() {
  local rows=() row key path name email
  mapfile -t rows < <(identity_rows)

  if [ "${#rows[@]}" -eq 0 ]; then
    printf 'No saved git-identity pairs.\n'
    return 0
  fi

  if has_tui; then
    paint_bold 63 'Saved identities'
  else
    printf 'Saved identities\n'
  fi

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r key path name email <<<"$row"
    if has_tui; then
      printf '%s  %s\n' "$(paint_bold 212 "${name:-<missing name>}")" "$(paint 86 "<${email:-missing email}>")"
      printf '  %s  %s\n' "$(paint 246 "$key")" "$(paint 240 "$path")"
    else
      printf '%s <%s> [%s]\n  %s\n' "${name:-<missing name>}" "${email:-missing email}" "$key" "$path"
    fi
  done
}

prompt_required() {
  local label="$1" default="${2:-}" value
  require_tui || return $?
  while true; do
    if [ -n "$default" ]; then
      value="$("$gum_bin" input --prompt "$label: " --value "$default" --prompt.foreground 63 --cursor.foreground 212)" || return 1
    else
      value="$("$gum_bin" input --prompt "$label: " --prompt.foreground 63 --cursor.foreground 212)" || return 1
    fi

    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi

    "$gum_bin" style --foreground 196 'Required.' >&2
  done
}

write_identity() {
  local key="$1" name="$2" email="$3" path
  ensure_manager
  path="$(identity_path_for_key "$key")"
  : >"$path"
  "$git_bin" config -f "$path" user.name "$name"
  "$git_bin" config -f "$path" user.email "$email"
}

add_identity() {
  local root="${1:-}" key name email default_key path
  require_tui || return $?

  if has_tui; then
    "$gum_bin" style --foreground 63 --bold 'Add new identity'
  fi

  name="$(prompt_required 'Name')" || return $?
  email="$(prompt_required 'Email')" || return $?
  default_key="${email%@*}"
  default_key="${default_key// /-}"

  while true; do
    key="$(prompt_required 'Label' "$default_key")" || return $?
    if ! validate_key "$key"; then
      "$gum_bin" style --foreground 196 'Use only letters, numbers, dot, dash, or underscore.' >&2
      continue
    fi

    path="$(identity_path_for_key "$key")"
    if [ -e "$path" ]; then
      "$gum_bin" style --foreground 196 'That label already exists.' >&2
      continue
    fi

    break
  done

  write_identity "$key" "$name" "$email"
  find_identity_by_key "$key"

  if [ -n "$root" ] && confirm_default_yes 'Use this identity for the current repo?'; then
    set_repo_identity_values "$root" "$name" "$email"
  fi
}

legacy_repo_identity_config_path() {
  local root="$1" git_dir
  git_dir="$($git_bin -C "$root" rev-parse --absolute-git-dir)"
  printf '%s/nixconf-identity.gitconfig\n' "$git_dir"
}

remove_legacy_repo_include() {
  local root="$1" include_file
  include_file="$(legacy_repo_identity_config_path "$root")"
  "$git_bin" -C "$root" config --local --fixed-value --unset-all include.path "$include_file" 2>/dev/null || true
  rm -f "$include_file"
}

set_repo_identity_values() {
  local root="$1" name="$2" email="$3"
  remove_legacy_repo_include "$root"
  "$git_bin" -C "$root" config --local user.name "$name"
  "$git_bin" -C "$root" config --local user.email "$email"
  "$git_bin" -C "$root" config --local user.useConfigOnly true

  if has_tui; then
    "$gum_bin" style --foreground 42 --bold 'Saved to this repo.'
  else
    printf 'saved to repo: %s <%s>\n' "$name" "$email"
  fi
}

set_repo_identity_by_key() {
  local key="$1" root="$2"
  if ! find_identity_by_key "$key"; then
    printf 'error: unknown identity: %s\n' "$key" >&2
    return 2
  fi
  set_repo_identity_values "$root" "$selected_identity_name" "$selected_identity_email"
}

edit_identity_by_key() {
  local key="$1" name email
  require_tui || return $?
  if ! find_identity_by_key "$key"; then
    printf 'error: unknown identity: %s\n' "$key" >&2
    return 2
  fi

  name="$(prompt_required 'Name' "$selected_identity_name")" || return $?
  email="$(prompt_required 'Email' "$selected_identity_email")" || return $?
  write_identity "$key" "$name" "$email"
  "$gum_bin" style --foreground 42 --bold 'Updated saved identity.'
}

delete_identity_by_key() {
  local key="$1"
  require_tui || return $?
  if ! find_identity_by_key "$key"; then
    printf 'error: unknown identity: %s\n' "$key" >&2
    return 2
  fi

  if confirm_default_yes "Delete $selected_identity_name <$selected_identity_email>?"; then
    rm -f "$selected_identity_path"
    "$gum_bin" style --foreground 42 --bold 'Deleted saved identity.'
  fi
}

identity_actions() {
  local root="$1" row="$2" action_index options=() key path name email
  IFS=$'\t' read -r key path name email <<<"$row"

  print_repo_card "$root"
  if has_tui; then
    "$gum_bin" style \
      --border rounded \
      --border-foreground 212 \
      --padding '0 1' \
      --margin '0 0 1 0' \
      "$(printf 'Identity\n%s <%s>\n%s' "$name" "$email" "$key")"
  fi

  if [ -n "$root" ]; then
    options+=("Use for this repo")
  fi
  options+=("Edit" "Delete")

  action_index="$(choose_index 'Identity action' "${options[@]}")" || return 0
  case "${options[$action_index]}" in
    'Use for this repo') set_repo_identity_values "$root" "$name" "$email" ;;
    'Edit') edit_identity_by_key "$key" ;;
    'Delete') delete_identity_by_key "$key" ;;
  esac
}

setup_repo() {
  local root rows=() options=() row selected_index add_option
  require_tui || return $?
  root="$(maybe_repo_root "$@")" || return $?

  print_repo_card "$root"

  mapfile -t rows < <(identity_rows)
  for row in "${rows[@]}"; do
    options+=("$(identity_option "$row")")
  done

  add_option="$(paint_bold 42 'Add new identity')"
  options+=("$add_option")

  selected_index="$(choose_index 'Select an identity' "${options[@]}")" || return 0
  if [ "$selected_index" -eq "${#rows[@]}" ]; then
    add_identity "$root"
  else
    identity_actions "$root" "${rows[$selected_index]}"
  fi
}

show_current() {
  local root
  root="$(require_repo_root "$@")" || return $?
  print_repo_card "$root"
}

show_current_with_origins() {
  local root
  root="$(require_repo_root "$@")" || return $?
  print_repo_card "$root"
  printf '\norigins:\n'
  "$git_bin" -C "$root" config --show-origin --get-regexp '^(user|commit|gpg)\.' || true
}

doctor() {
  local root name email
  root="$(require_repo_root "$@")" || return $?
  name="$($git_bin -C "$root" config --get user.name 2>/dev/null || true)"
  email="$($git_bin -C "$root" config --get user.email 2>/dev/null || true)"

  if [ -z "$name" ] || [ -z "$email" ]; then
    printf 'error: %s has no complete Git identity\n' "$root" >&2
    printf 'hint: run gi, gid, or git-identity setup\n' >&2
    return 1
  fi

  printf 'ok: %s <%s>\n' "$name" "$email"
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
    setup|manage) setup_repo "$@" ;;
    current) show_current "$@" ;;
    origins) show_current_with_origins "$@" ;;
    doctor) doctor "$@" ;;
    list) print_identity_list ;;
    add)
      local root
      root="$(maybe_repo_root "$@")" || return $?
      add_identity "$root"
      ;;
    use)
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        printf 'usage: git-identity use <identity> [repo]\n' >&2
        return 2
      fi
      local identity="$1" target="${2:-.}" repo_root
      repo_root="$(git_repo_root "$target")" || {
        printf 'error: not a git repository: %s\n' "$target" >&2
        return 2
      }
      set_repo_identity_by_key "$identity" "$repo_root"
      ;;
    edit)
      if [ "$#" -ne 1 ]; then
        printf 'usage: git-identity edit <identity>\n' >&2
        return 2
      fi
      edit_identity_by_key "$1"
      ;;
    delete|rm)
      if [ "$#" -ne 1 ]; then
        printf 'usage: git-identity delete <identity>\n' >&2
        return 2
      fi
      delete_identity_by_key "$1"
      ;;
    global)
      printf 'error: global git-identity rules were removed; use "git-identity use <identity> [repo]" for repo-local user.name/user.email\n' >&2
      return 2
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
