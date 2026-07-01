#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script reads root-only Infisical client credentials. Re-run with sudo." >&2
  exit 1
fi

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


ensure_folder() {
  local infisical_path="$1"
  [[ "$infisical_path" == "/" ]] && return 0

  local trimmed="${infisical_path#/}"
  local current="/"
  local part
  IFS='/' read -r -a parts <<<"$trimmed"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    sudo docker exec \
      -e INFISICAL_TOKEN="$INFISICAL_TOKEN" \
      -e INFISICAL_PROJECT_ID="$INFISICAL_PROJECT_ID" \
      -e INFISICAL_DOMAIN="$INFISICAL_DOMAIN" \
      -e INFISICAL_ENV="$INFISICAL_ENV" \
      lab-infisical sh -c '
        infisical secrets folders create \
          --name "$1" \
          --path "$2" \
          --domain "$INFISICAL_DOMAIN" \
          --token "$INFISICAL_TOKEN" \
          --projectId "$INFISICAL_PROJECT_ID" \
          --env "$INFISICAL_ENV" \
          --silent >/dev/null 2>&1 || true
      ' sh "$part" "$current"
    if [[ "$current" == "/" ]]; then
      current="/${part}"
    else
      current="${current}/${part}"
    fi
  done
}

verify_file_secrets() {
  local infisical_path="$1"
  local file="$2"
  local key
  while IFS='=' read -r key _; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
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
          --silent >/dev/null
      ' sh "$key" "$infisical_path"
  done <"$file"
}
set_from_file() {
  local infisical_path="$1"
  local file="$2"
  ensure_folder "$infisical_path"
  if [[ ! -s "$file" ]]; then
    echo "missing or empty import file: $file" >&2
    exit 1
  fi
  sudo docker exec -i \
    -e INFISICAL_TOKEN="$INFISICAL_TOKEN" \
    -e INFISICAL_PROJECT_ID="$INFISICAL_PROJECT_ID" \
    -e INFISICAL_DOMAIN="$INFISICAL_DOMAIN" \
    -e INFISICAL_ENV="$INFISICAL_ENV" \
    lab-infisical sh -c '
      tmp="$(mktemp)"
      cat >"$tmp"
      infisical secrets set \
        --file "$tmp" \
        --domain "$INFISICAL_DOMAIN" \
        --token "$INFISICAL_TOKEN" \
        --projectId "$INFISICAL_PROJECT_ID" \
        --env "$INFISICAL_ENV" \
        --path "$1" \
        --silent >/dev/null
      rm -f "$tmp"
    ' sh "$infisical_path" <"$file"
  verify_file_secrets "$infisical_path" "$file"
}

select_keys() {
  local source_file="$1"
  shift
  python3 - "$source_file" "$@" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1])
keys = set(sys.argv[2:])
for line in source.read_text().splitlines():
    if not line or line.lstrip().startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    if k in keys:
        print(f'{k}={v}')
PY
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Existing inline registry secret is low-value bootstrap material; rotate to a new Infisical-generated value.
openssl rand -base64 48 | tr -d '\n' | awk '{print "REGISTRY_HTTP_SECRET="$0}' >"$workdir/docker-registry.env"
set_from_file /docker-registry "$workdir/docker-registry.env"

select_keys /data/homelab/lab/legacy-secrets/nexus-admin.env \
  ADMIN_PASSWORD \
  RESEND_API_KEY \
  S3_ACCESS_KEY_ID \
  S3_SECRET_ACCESS_KEY \
  SUPABASE_SECRET_KEY >"$workdir/nexus-admin.env"
set_from_file /nexus-admin "$workdir/nexus-admin.env"

select_keys /data/homelab/lab/legacy-secrets/rsshub.env \
  TWITTER_AUTH_TOKEN >"$workdir/rsshub.env"
set_from_file /rsshub "$workdir/rsshub.env"

select_keys /data/homelab/lab/legacy-secrets/system-monitoring.env \
  MIHOMO_API_TOKEN >"$workdir/system-monitoring.env"
set_from_file /system-monitoring "$workdir/system-monitoring.env"

echo "Legacy secrets imported to Infisical paths: /docker-registry, /nexus-admin, /rsshub, /system-monitoring" >&2
