#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run nginx-managed-subdomains as root (for nginx reload + ACME writes)." >&2
  exit 1
fi

STATE_DIR="${STATE_DIR:?}"
DATA_FILE="${DATA_FILE:?}"
SITES_DIR="${SITES_DIR:?}"
WEBROOT="${WEBROOT:?}"
CERTBOT_DIR="${CERTBOT_DIR:?}"
ACME_EMAIL="${ACME_EMAIL:?}"
TRAEFIK_UPSTREAM="${TRAEFIK_UPSTREAM:?}"
AUTH_GATEWAY_BASE_URL="${AUTH_GATEWAY_BASE_URL:?}"
AUTH_COOKIE_DOMAIN="${AUTH_COOKIE_DOMAIN:?}"
AUTH_COOKIE_NAME="${AUTH_COOKIE_NAME:?}"
AUTH_RETURN_COOKIE_NAME="${AUTH_RETURN_COOKIE_NAME:?}"
STATIC_HOSTS_FILE="${STATIC_HOSTS_FILE:?}"

readonly CERTBOT_CONFIG_DIR="${CERTBOT_DIR}/config"
readonly CERTBOT_WORK_DIR="${CERTBOT_DIR}/work"
readonly CERTBOT_LOGS_DIR="${CERTBOT_DIR}/logs"
readonly MANAGED_DOMAIN_SUFFIX=".my-website.space"

mkdir -p "${STATE_DIR}" "${SITES_DIR}" "${WEBROOT}" "${CERTBOT_CONFIG_DIR}" "${CERTBOT_WORK_DIR}" "${CERTBOT_LOGS_DIR}"
touch "${DATA_FILE}" "${SITES_DIR}/_empty.conf"

show_info() {
  gum style --foreground 81 "$1"
}

show_error() {
  gum style --foreground 196 "$1" >&2
}

show_success() {
  gum style --foreground 42 "$1"
}

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

require_valid_hostname() {
  local hostname="$1"

  if [[ -z "${hostname}" ]]; then
    show_error "Hostname cannot be empty."
    return 1
  fi

  if [[ ! "${hostname}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.my-website\.space$ ]]; then
    show_error "Hostnames must be lowercase and end in ${MANAGED_DOMAIN_SUFFIX}"
    return 1
  fi

  if grep -Fxq "${hostname}" "${STATIC_HOSTS_FILE}"; then
    show_error "${hostname} is already managed declaratively in Nix."
    return 1
  fi

  return 0
}

prompt_hostname() {
  local prompt="$1"
  local placeholder="$2"
  local allow_empty="$3"
  local hostname

  hostname=$(gum input --prompt "${prompt}" --placeholder "${placeholder}") || return 1
  hostname=$(trim_whitespace "${hostname}")

  if [[ -z "${hostname}" && "${allow_empty}" == "allow-empty" ]]; then
    return 0
  fi

  if [[ -z "${hostname}" ]]; then
    show_info "No hostname entered. Nothing changed."
    return 1
  fi

  printf '%s' "${hostname}"
}

record_exists() {
  local hostname="$1"
  awk -F '\t' -v host="${hostname}" '$1 == host { found = 1 } END { exit(found ? 0 : 1) }' "${DATA_FILE}"
}

get_mode() {
  local hostname="$1"
  awk -F '\t' -v host="${hostname}" '$1 == host { print $2; exit }' "${DATA_FILE}"
}

list_records_from_file() {
  local file_path="$1"

  awk -F '\t' '
    BEGIN {
      host_pattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\\.my-website\\.space$"
    }
    {
      host = $1
      mode = $2
      sub(/^[[:space:]]+/, "", host)
      sub(/[[:space:]]+$/, "", host)
      sub(/^[[:space:]]+/, "", mode)
      sub(/[[:space:]]+$/, "", mode)

      if (host ~ host_pattern && (mode == "authenticated" || mode == "unauthenticated")) {
        printf "%s\t%s\n", host, mode
      }
    }
  ' "${file_path}"
}

list_records() {
  list_records_from_file "${DATA_FILE}" | sort -t $'\t' -k1,1
}

write_records() {
  local tmp
  tmp=$(mktemp)
  cat >"${tmp}"
  list_records_from_file "${tmp}" | sort -t $'\t' -k1,1 -u >"${DATA_FILE}"
  rm -f "${tmp}"
}

sanitize_data_file() {
  write_records <"${DATA_FILE}"
}

replace_record() {
  local old_host="$1"
  local new_host="$2"
  local new_mode="$3"
  local tmp
  tmp=$(mktemp)
  awk -F '\t' -v old="${old_host}" '$1 != old { print }' "${DATA_FILE}" >"${tmp}"
  printf '%s\t%s\n' "${new_host}" "${new_mode}" >>"${tmp}"
  write_records <"${tmp}"
  rm -f "${tmp}"
}

append_record() {
  local hostname="$1"
  local mode="$2"
  printf '%s\t%s\n' "${hostname}" "${mode}" >>"${DATA_FILE}"
  write_records <"${DATA_FILE}"
}

remove_record() {
  local hostname="$1"
  local tmp
  tmp=$(mktemp)
  awk -F '\t' -v host="${hostname}" '$1 != host { print }' "${DATA_FILE}" >"${tmp}"
  write_records <"${tmp}"
  rm -f "${tmp}"
}

cert_paths_exist() {
  local hostname="$1"
  [[ -f "${CERTBOT_CONFIG_DIR}/live/${hostname}/fullchain.pem" && -f "${CERTBOT_CONFIG_DIR}/live/${hostname}/privkey.pem" ]]
}

purge_certificate_state() {
  local hostname="$1"

  rm -rf \
    "${CERTBOT_CONFIG_DIR}/live/${hostname}" \
    "${CERTBOT_CONFIG_DIR}/archive/${hostname}" \
    "${CERTBOT_CONFIG_DIR}/renewal/${hostname}.conf"
}

render_acme_location() {
  cat <<EOF
  location ^~ /.well-known/acme-challenge/ {
    root ${WEBROOT};
    default_type text/plain;
    try_files \$uri =404;
    # Runtime-created hosts share the declarative ACME webroot so HTTP-01
    # validation still succeeds before the host has its final HTTPS server.
    auth_basic off;
    auth_request off;
  }
EOF
}

render_auth_locations() {
  cat <<EOF
  location = /_services-auth/check {
    internal;
    proxy_pass ${AUTH_GATEWAY_BASE_URL}/api/check;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Cookie \$http_cookie;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Original-Host \$host;
    proxy_set_header X-Original-URI \$request_uri;
  }

  location @services-auth-login {
    add_header Set-Cookie "${AUTH_RETURN_COOKIE_NAME}=\$scheme://\$http_host\$request_uri; Domain=${AUTH_COOKIE_DOMAIN}; Path=/; Max-Age=300; HttpOnly; Secure; SameSite=Lax" always;
    return 302 https://auth.my-website.space/login;
  }
EOF
}

render_proxy_location() {
  local mode="$1"

  cat <<EOF
  location / {
    proxy_pass ${TRAEFIK_UPSTREAM}/;
    proxy_http_version 1.1;
    # Preserve the browser hostname so Traefik can keep routing on Host rules
    # instead of falling back to a catch-all backend that would 404.
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Upgrade \$http_upgrade;
    # Use an explicitly declared map from nginx config so runtime snippets do
    # not silently depend on an implicit global variable.
    proxy_set_header Connection \$managed_subdomains_connection_upgrade;
EOF

  if [[ "${mode}" == "authenticated" ]]; then
    cat <<'EOF'
    auth_request /_services-auth/check;
    error_page 401 = @services-auth-login;
EOF
  fi

  cat <<'EOF'
  }
EOF
}

restore_records_from_backup() {
  local backup_file="$1"

  cp "${backup_file}" "${DATA_FILE}"
}

apply_rendered_config() {
  render_all_configs
  reload_after_validation
}

render_site_config() {
  local hostname="$1"
  local mode="$2"
  local conf_file="${SITES_DIR}/${hostname}.conf"
  local cert_dir="${CERTBOT_CONFIG_DIR}/live/${hostname}"

  cat >"${conf_file}" <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${hostname};

$(render_acme_location)

  location / {
    return 301 https://\$host\$request_uri;
  }
}
EOF

  if ! cert_paths_exist "${hostname}"; then
    return 0
  fi

  cat >>"${conf_file}" <<EOF

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${hostname};

  ssl_certificate ${cert_dir}/fullchain.pem;
  ssl_certificate_key ${cert_dir}/privkey.pem;

EOF

  {
    if [[ "${mode}" == "authenticated" ]]; then
      render_auth_locations
      printf '\n'
    fi

    render_acme_location
    printf '\n'
    render_proxy_location "${mode}"
    cat <<'EOF'
}
EOF
  } >>"${conf_file}"
}

render_all_configs() {
  rm -f "${SITES_DIR}"/*.conf
  touch "${SITES_DIR}/_empty.conf"

  while IFS=$'\t' read -r hostname mode; do
    [[ -z "${hostname}" ]] && continue
    render_site_config "${hostname}" "${mode}"
  done < <(list_records)
}

reload_nginx() {
  systemctl reload nginx.service --no-block
}

validate_nginx() {
  if ! systemctl status nginx.service --no-pager >/dev/null 2>&1; then
    show_error "nginx.service is not available yet on this host. Rebuild/apply the system config first."
    return 1
  fi

  if ! nginx -t; then
    show_error "nginx configuration test failed."
    return 1
  fi
}

reload_after_validation() {
  validate_nginx || return 1
  systemctl reload nginx
}

issue_certificate() {
  local hostname

  hostname=$(trim_whitespace "$1")
  require_valid_hostname "${hostname}" || return 1

  # Failed ACME attempts can leave stale per-host state in the persistent
  # custom certbot config dir. Start fresh for initial issuance whenever the
  # expected certificate files do not exist yet.
  if ! cert_paths_exist "${hostname}"; then
    purge_certificate_state "${hostname}"
  fi

  certbot certonly \
    --webroot \
    --webroot-path "${WEBROOT}" \
    --agree-tos \
    --non-interactive \
    --keep-until-expiring \
    --email "${ACME_EMAIL}" \
    --config-dir "${CERTBOT_CONFIG_DIR}" \
    --work-dir "${CERTBOT_WORK_DIR}" \
    --logs-dir "${CERTBOT_LOGS_DIR}" \
    -d "${hostname}"
}

provision_host() {
  local hostname="$1"
  local mode="$2"

  apply_rendered_config

  if ! issue_certificate "${hostname}"; then
    show_error "ACME issuance failed for ${hostname}. Rolling back the new record."
    remove_record "${hostname}"
    purge_certificate_state "${hostname}"
    apply_rendered_config
    return 1
  fi

  if ! cert_paths_exist "${hostname}"; then
    show_error "Certificate files are still missing for ${hostname}. Rolling back the new record."
    remove_record "${hostname}"
    purge_certificate_state "${hostname}"
    apply_rendered_config
    return 1
  fi

  apply_rendered_config
  show_success "${hostname} is now configured with HTTPS."
}

pick_mode() {
  gum choose "authenticated" "unauthenticated"
}

pick_record() {
  local lines
  lines=$(list_records | awk -F '\t' '{ printf "%s [%s]\n", $1, $2 }')
  [[ -z "${lines}" ]] && return 1
  gum filter --header "Select a managed subdomain" <<<"${lines}"
}

parse_selected_hostname() {
  local selection="$1"
  local hostname="${selection%% \[*}"

  hostname=$(trim_whitespace "${hostname}")
  [[ -n "${hostname}" ]] || return 1
  require_valid_hostname "${hostname}" || return 1

  printf '%s' "${hostname}"
}

add_interactive() {
  local hostname mode
  hostname=$(prompt_hostname "Hostname> " "openclaw.my-website.space" "require-value") || return 0
  require_valid_hostname "${hostname}" || return 1

  if record_exists "${hostname}"; then
    show_error "${hostname} is already managed."
    return 1
  fi

  mode=$(pick_mode) || {
    show_info "No mode selected. Nothing changed."
    return 0
  }
  append_record "${hostname}" "${mode}"
  provision_host "${hostname}" "${mode}"
}

edit_interactive() {
  local selection current_host current_mode new_host new_mode backup_file
  selection=$(pick_record) || {
    if [[ -n "$(list_records)" ]]; then
      show_info "No subdomain selected."
    else
      show_info "No managed subdomains yet."
    fi
    return 0
  }
  current_host=$(parse_selected_hostname "${selection}") || {
    show_info "No subdomain selected."
    return 0
  }
  current_mode=$(get_mode "${current_host}")

  new_host=$(prompt_hostname "Hostname> " "${current_host}" "allow-empty") || {
    show_info "No subdomain selected."
    return 0
  }
  if [[ -z "${new_host}" ]]; then
    new_host="${current_host}"
  fi
  require_valid_hostname "${new_host}" || return 1

  if [[ "${new_host}" != "${current_host}" ]] && record_exists "${new_host}"; then
    show_error "${new_host} is already managed."
    return 1
  fi

  new_mode=$(gum choose "${current_mode}" "$([[ "${current_mode}" == authenticated ]] && printf '%s' unauthenticated || printf '%s' authenticated)")

  backup_file=$(mktemp)
  cp "${DATA_FILE}" "${backup_file}"

  if [[ "${new_host}" != "${current_host}" ]]; then
    # Keep the existing host live until the replacement hostname has a working
    # certificate, otherwise nginx falls back to another TLS vhost and serves a
    # misleading default certificate/404 during the rename window.
    append_record "${new_host}" "${new_mode}"
    apply_rendered_config

    if ! issue_certificate "${new_host}"; then
      remove_record "${new_host}"
      restore_records_from_backup "${backup_file}"
      purge_certificate_state "${new_host}"
      apply_rendered_config
      rm -f "${backup_file}"
      show_error "ACME issuance failed for ${new_host}; restored previous record."
      return 1
    fi

    if ! cert_paths_exist "${new_host}"; then
      remove_record "${new_host}"
      restore_records_from_backup "${backup_file}"
      purge_certificate_state "${new_host}"
      apply_rendered_config
      rm -f "${backup_file}"
      show_error "Certificate files are still missing for ${new_host}; restored previous record."
      return 1
    fi

    remove_record "${current_host}"
    certbot delete \
      --non-interactive \
      --cert-name "${current_host}" \
      --config-dir "${CERTBOT_CONFIG_DIR}" \
      --work-dir "${CERTBOT_WORK_DIR}" \
      --logs-dir "${CERTBOT_LOGS_DIR}" >/dev/null 2>&1 || true
    purge_certificate_state "${current_host}"
  else
    replace_record "${current_host}" "${new_host}" "${new_mode}"
  fi

  apply_rendered_config
  rm -f "${backup_file}"
  show_success "Updated ${new_host}."
}

delete_interactive() {
  local selection hostname
  selection=$(pick_record) || {
    if [[ -n "$(list_records)" ]]; then
      show_info "No subdomain selected."
    else
      show_info "No managed subdomains yet."
    fi
    return 0
  }
  hostname=$(parse_selected_hostname "${selection}") || {
    show_info "No subdomain selected."
    return 0
  }

  if ! gum confirm "Delete ${hostname} and its managed certificate?"; then
    return 0
  fi

  remove_record "${hostname}"
  certbot delete \
    --non-interactive \
    --cert-name "${hostname}" \
    --config-dir "${CERTBOT_CONFIG_DIR}" \
    --work-dir "${CERTBOT_WORK_DIR}" \
    --logs-dir "${CERTBOT_LOGS_DIR}" >/dev/null 2>&1 || true
  purge_certificate_state "${hostname}"
  rm -f "${SITES_DIR}/${hostname}.conf"
  apply_rendered_config
  show_success "Deleted ${hostname}."
}

issue_missing_certificates() {
  local hostname mode

  while IFS=$'\t' read -r hostname mode; do
    [[ -z "${hostname}" ]] && continue

    if ! cert_paths_exist "${hostname}"; then
      issue_certificate "${hostname}" || return 1
      cert_paths_exist "${hostname}" || {
        show_error "Certificate files are still missing for ${hostname} after issuance."
        return 1
      }
    fi
  done < <(list_records)
}

list_interactive() {
  local output
  output=$(list_records | awk -F '\t' 'BEGIN { printf "HOSTNAME\tMODE\n" } { printf "%s\t%s\n", $1, $2 }')
  if [[ -z "${output}" || "${output}" == $'HOSTNAME\tMODE' ]]; then
    show_info "No managed subdomains yet."
    return 0
  fi

  printf '%s\n' "${output}"
}

renew_all() {
  if ! certbot renew \
    --non-interactive \
    --webroot \
    --webroot-path "${WEBROOT}" \
    --config-dir "${CERTBOT_CONFIG_DIR}" \
    --work-dir "${CERTBOT_WORK_DIR}" \
    --logs-dir "${CERTBOT_LOGS_DIR}"; then
    show_error "certbot renew failed."
    return 1
  fi

  render_all_configs
  reload_after_validation
  show_success "Managed certificates renewed and nginx reloaded."
}

regenerate_only() {
  issue_missing_certificates || return 1
  render_all_configs
  reload_after_validation
  show_success "Managed nginx configs regenerated."
}

main_menu() {
  gum choose \
    --header "Managed nginx subdomains" \
    "Add subdomain" \
    "Edit subdomain" \
    "Delete subdomain" \
    "List subdomains" \
    "Regenerate configs" \
    "Renew certificates" \
    "Quit"
}

interactive_main() {
  local selection

  sanitize_data_file

  while true; do
    selection=$(main_menu) || exit 0

    case "${selection}" in
    "Add subdomain") add_interactive ;;
    "Edit subdomain") edit_interactive ;;
    "Delete subdomain") delete_interactive ;;
    "List subdomains") list_interactive ;;
    "Regenerate configs") regenerate_only ;;
    "Renew certificates") renew_all ;;
    "Quit") exit 0 ;;
    esac
  done
}

case "${1:-interactive}" in
interactive)
  interactive_main
  ;;
regenerate)
  sanitize_data_file
  regenerate_only
  ;;
renew-all)
  sanitize_data_file
  renew_all
  ;;
*)
  echo "Usage: nginx-managed-subdomains [interactive|regenerate|renew-all]" >&2
  exit 1
  ;;
esac
