#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script materializes root-only secrets. Re-run as root." >&2
  exit 1
fi

homelab_root="${HOMELAB_ROOT:-/home/skywt/homelab}"
materializer="${homelab_root}/scripts/materialize-secrets.sh"
infisical_wait_seconds="${INFISICAL_WAIT_SECONDS:-300}"
compose_start_timeout_seconds="${COMPOSE_START_TIMEOUT_SECONDS:-180}"

if [[ ! -x "${materializer}" ]]; then
  echo "missing executable secret materializer: ${materializer}" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

echo "Waiting for Infisical and materializing service secrets"
deadline=$((SECONDS + infisical_wait_seconds))
until "${materializer}" all; do
  if (( SECONDS >= deadline )); then
    echo "Infisical did not become ready within ${infisical_wait_seconds}s" >&2
    exit 1
  fi

  sleep 5
done

# Keep Immich last so an unavailable NAS/NFS export cannot delay recovery of
# the services whose storage is local to lab.
services=(
  android-scrcpy
  docker-registry
  nexus-admin
  radicale
  radicale-todo
  rsshub
  system-monitoring
  vaultwarden
  webhook
  immich
)

failures=()
for service in "${services[@]}"; do
  compose_file="${homelab_root}/services/${service}/compose.yml"
  if [[ ! -r "${compose_file}" ]]; then
    echo "missing Compose file for ${service}: ${compose_file}" >&2
    failures+=("${service}")
    continue
  fi

  echo "Restoring ${service}"
  if ! timeout --foreground "${compose_start_timeout_seconds}" \
    docker compose -f "${compose_file}" up -d; then
    echo "failed to restore ${service}" >&2
    failures+=("${service}")
  fi
done

if (( ${#failures[@]} > 0 )); then
  printf 'Services not restored: %s\n' "${failures[*]}" >&2
  exit 1
fi

echo "All secret-dependent services have been restored"
