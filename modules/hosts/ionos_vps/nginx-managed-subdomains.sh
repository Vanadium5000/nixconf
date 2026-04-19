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

require_valid_hostname() {
  local hostname="$1"

  if [[ -z "${hostname}" ]]; then
    show_error "Hostname cannot be empty."
    return 1
  fi

  if [[ ! "${hostname}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.my-website\.space$ ]]; then
    show_error "Hostnames must be lowercase and end in .my-website.space"
    return 1
  fi

  if grep -Fxq "${hostname}" "${STATIC_HOSTS_FILE}"; then
    show_error "${hostname} is already managed declaratively in Nix."
    return 1
  fi

  return 0
}

record_exists() {
  local hostname="$1"
  awk -F '\t' -v host="${hostname}" '$1 == host { found = 1 } END { exit(found ? 0 : 1) }' "${DATA_FILE}"
}

get_mode() {
  local hostname="$1"
  awk -F '\t' -v host="${hostname}" '$1 == host { print $2; exit }' "${DATA_FILE}"
}

list_records() {
  grep -v '^[[:space:]]*$' "${DATA_FILE}" | sort -t $'\t' -k1,1
}

write_records() {
  local tmp
  tmp=$(mktemp)
  cat > "${tmp}"
  sort -t $'\t' -k1,1 -u "${tmp}" > "${DATA_FILE}"
  rm -f "${tmp}"
}

replace_record() {
  local old_host="$1"
  local new_host="$2"
  local new_mode="$3"
  local tmp
  tmp=$(mktemp)
  awk -F '\t' -v old="${old_host}" '$1 != old { print }' "${DATA_FILE}" > "${tmp}"
  printf '%s\t%s\n' "${new_host}" "${new_mode}" >> "${tmp}"
  write_records < "${tmp}"
  rm -f "${tmp}"
}

append_record() {
  local hostname="$1"
  local mode="$2"
  printf '%s\t%s\n' "${hostname}" "${mode}" >> "${DATA_FILE}"
  write_records < "${DATA_FILE}"
}

remove_record() {
  local hostname="$1"
  local tmp
  tmp=$(mktemp)
  awk -F '\t' -v host="${hostname}" '$1 != host { print }' "${DATA_FILE}" > "${tmp}"
  write_records < "${tmp}"
  rm -f "${tmp}"
}

cert_paths_exist() {
  local hostname="$1"
  [[ -f "${CERTBOT_CONFIG_DIR}/live/${hostname}/fullchain.pem" && -f "${CERTBOT_CONFIG_DIR}/live/${hostname}/privkey.pem" ]]
}

render_site_config() {
  local hostname="$1"
  local mode="$2"
  local conf_file="${SITES_DIR}/${hostname}.conf"
  local cert_dir="${CERTBOT_CONFIG_DIR}/live/${hostname}"

  cat > "${conf_file}" <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${hostname};

  location ^~ /.well-known/acme-challenge/ {
    root ${WEBROOT};
    default_type text/plain;
    try_files \$uri =404;
  }

  location / {
    return 301 https://\$host\$request_uri;
  }
}
EOF

  if ! cert_paths_exist "${hostname}"; then
    return 0
  fi

  cat >> "${conf_file}" <<EOF

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${hostname};

  ssl_certificate ${cert_dir}/fullchain.pem;
  ssl_certificate_key ${cert_dir}/privkey.pem;

EOF

  if [[ "${mode}" == "authenticated" ]]; then
    cat >> "${conf_file}" <<EOF
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
  fi

  cat >> "${conf_file}" <<EOF
  location / {
    proxy_pass ${TRAEFIK_UPSTREAM}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
EOF

  if [[ "${mode}" == "authenticated" ]]; then
    cat >> "${conf_file}" <<EOF
    auth_request /_services-auth/check;
    error_page 401 = @services-auth-login;
EOF
  fi

  cat >> "${conf_file}" <<'EOF'
  }
}
EOF
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
  local hostname="$1"

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

  render_all_configs
  reload_after_validation

  if ! issue_certificate "${hostname}"; then
    show_error "ACME issuance failed for ${hostname}. Rolling back the new record."
    remove_record "${hostname}"
    render_all_configs
    reload_after_validation
    return 1
  fi

  render_all_configs
  reload_after_validation
  show_success "${hostname} is now configured with HTTPS."
}

pick_mode() {
  gum choose "authenticated" "unauthenticated"
}

pick_record() {
  local lines
  lines=$(list_records | awk -F '\t' '{ printf "%s [%s]\n", $1, $2 }')
  [[ -z "${lines}" ]] && return 1
  gum filter --header "Select a managed subdomain" <<< "${lines}"
}

add_interactive() {
  local hostname mode
  hostname=$(gum input --prompt "Hostname> " --placeholder "openclaw.my-website.space")
  require_valid_hostname "${hostname}" || return 1

  if record_exists "${hostname}"; then
    show_error "${hostname} is already managed."
    return 1
  fi

  mode=$(pick_mode)
  append_record "${hostname}" "${mode}"
  provision_host "${hostname}" "${mode}"
}

edit_interactive() {
  local selection current_host current_mode new_host new_mode backup_file
  selection=$(pick_record) || {
    show_info "No managed subdomains yet."
    return 0
  }
  current_host="${selection%% \[*}"
  current_mode=$(get_mode "${current_host}")

  new_host=$(gum input --prompt "Hostname> " --placeholder "${current_host}")
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

  replace_record "${current_host}" "${new_host}" "${new_mode}"
  render_all_configs
  reload_after_validation

  if [[ "${new_host}" != "${current_host}" ]]; then
    if ! issue_certificate "${new_host}"; then
      cp "${backup_file}" "${DATA_FILE}"
      render_all_configs
      reload_after_validation
      rm -f "${backup_file}"
      show_error "ACME issuance failed for ${new_host}; restored previous record."
      return 1
    fi
  fi

  render_all_configs
  reload_after_validation
  rm -f "${backup_file}"
  show_success "Updated ${new_host}."
}

delete_interactive() {
  local selection hostname
  selection=$(pick_record) || {
    show_info "No managed subdomains yet."
    return 0
  }
  hostname="${selection%% \[*}"

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
  rm -f "${SITES_DIR}/${hostname}.conf"
  render_all_configs
  reload_after_validation
  show_success "Deleted ${hostname}."
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

show_dashboard() {
  gum style --foreground 212 --bold "Managed nginx subdomains"
  list_interactive
  printf '\n'
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
  while true; do
    clear
    show_dashboard
    case "$(main_menu)" in
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
    regenerate_only
    ;;
  renew-all)
    renew_all
    ;;
  *)
    echo "Usage: nginx-managed-subdomains [interactive|regenerate|renew-all]" >&2
    exit 1
    ;;
esac
