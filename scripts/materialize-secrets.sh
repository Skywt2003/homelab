#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <service|all>" >&2
  exit 2
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script reads root-only Infisical client credentials. Re-run with sudo." >&2
  exit 1
fi

action="$1"
client_env="${INFISICAL_CLIENT_ENV:-/data/homelab/lab/infisical/client.env}"
if [[ ! -r "$client_env" ]]; then
  echo "missing or unreadable Infisical client env: $client_env" >&2
  echo "expected root-only file with INFISICAL_TOKEN and INFISICAL_PROJECT_ID" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$client_env"
: "${INFISICAL_PROJECT_ID:?set INFISICAL_PROJECT_ID in $client_env}"
INFISICAL_DOMAIN="${INFISICAL_DOMAIN:-http://127.0.0.1:8080}"
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

get_access_token() {
  if [[ -n "${INFISICAL_TOKEN:-}" ]]; then
    printf '%s' "$INFISICAL_TOKEN"
    return
  fi

  : "${INFISICAL_CLIENT_ID:?set INFISICAL_TOKEN or INFISICAL_CLIENT_ID in $client_env}"
  : "${INFISICAL_CLIENT_SECRET:?set INFISICAL_TOKEN or INFISICAL_CLIENT_SECRET in $client_env}"

  sudo docker exec     -e INFISICAL_DOMAIN="$INFISICAL_DOMAIN"     -e INFISICAL_CLIENT_ID="$INFISICAL_CLIENT_ID"     -e INFISICAL_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"     lab-infisical sh -c '
      infisical login         --domain "$INFISICAL_DOMAIN"         --method universal-auth         --client-id "$INFISICAL_CLIENT_ID"         --client-secret "$INFISICAL_CLIENT_SECRET"         --plain         --silent
    '
}

INFISICAL_TOKEN="$(get_access_token)"

infisical_get() {
  local secret_name="$1"
  local secret_path="$2"
  sudo docker exec \
    -e INFISICAL_TOKEN="$INFISICAL_TOKEN" \
    -e INFISICAL_PROJECT_ID="$INFISICAL_PROJECT_ID" \
    -e INFISICAL_DOMAIN="$INFISICAL_DOMAIN" \
    -e INFISICAL_ENV="$INFISICAL_ENV" \
    lab-infisical sh -c '
      infisical secrets get "$1" \
        --domain "$INFISICAL_DOMAIN" \
        --token "$INFISICAL_TOKEN" \
        --projectId "$INFISICAL_PROJECT_ID" \
        --env "$INFISICAL_ENV" \
        --path "$2" \
        --plain \
        --silent
    ' sh "$secret_name" "$secret_path"
}

write_secret() {
  local service="$1"
  local infisical_path="$2"
  local infisical_name="$3"
  local file_name="$4"
  local mode="${5:-0400}"
  local secret_dir="/run/homelab/secrets/${service}"
  local tmp

  sudo install -d -m 0700 "$secret_dir"
  tmp="$(mktemp)"
  infisical_get "$infisical_name" "$infisical_path" >"$tmp"
  sudo install -m "$mode" "$tmp" "$secret_dir/$file_name"
  rm -f "$tmp"
}

materialize_docker_registry() {
  write_secret docker-registry /docker-registry REGISTRY_HTTP_SECRET http_secret
}

materialize_immich() {
  write_secret immich /immich DB_PASSWORD database_password
}

materialize_android_scrcpy() {
  write_secret android-scrcpy /android-scrcpy VNC_PASSWORD vnc_password
}

materialize_nexus_admin() {
  write_secret nexus-admin /nexus-admin ADMIN_PASSWORD admin_password
  write_secret nexus-admin /nexus-admin RESEND_API_KEY resend_api_key
  write_secret nexus-admin /nexus-admin S3_ACCESS_KEY_ID s3_access_key_id
  write_secret nexus-admin /nexus-admin S3_SECRET_ACCESS_KEY s3_secret_access_key
  write_secret nexus-admin /nexus-admin SUPABASE_SECRET_KEY supabase_secret_key
}

materialize_radicale() {
  # Compose implements file-backed secrets as bind mounts, so uid/gid/mode
  # overrides are ignored. The host directory remains root-only (0700), while
  # the mounted file must be readable by Radicale's UID 2999 in the container.
  write_secret radicale /radicale USERS users 0444
}

materialize_rsshub() {
  write_secret rsshub /rsshub TWITTER_AUTH_TOKEN twitter_auth_token
}

materialize_system_monitoring() {
  # The exporter runs as a non-root user and reads this through MIHOMO_API_TOKEN_FILE.
  write_secret system-monitoring /system-monitoring MIHOMO_API_TOKEN mihomo_api_token 0444
}

case "$action" in
  android-scrcpy) materialize_android_scrcpy ;;
  docker-registry) materialize_docker_registry ;;
  immich) materialize_immich ;;
  nexus-admin) materialize_nexus_admin ;;
  radicale) materialize_radicale ;;
  rsshub) materialize_rsshub ;;
  system-monitoring) materialize_system_monitoring ;;
  all)
    materialize_android_scrcpy
    materialize_docker_registry
    materialize_immich
    materialize_nexus_admin
    materialize_radicale
    materialize_rsshub
    materialize_system_monitoring
    ;;
  *)
    echo "unknown service: $action" >&2
    exit 2
    ;;
esac
