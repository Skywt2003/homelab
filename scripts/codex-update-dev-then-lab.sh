#!/usr/bin/env bash
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG_DIR="/home/skywt/homelab/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/codex-update.log"
APPRISE_NOTIFY_URL="https://notify.lab.skywt/notify/apprise"
CURRENT_STAGE="startup"
# Use the canonical FQDN. The short `proxy` alias intermittently resolves but
# resets CONNECT traffic on lab, while the FQDN and its Tailnet address work.
CODEX_PROXY_URL="http://proxy.skynet:10810"

send_failure_notification() {
  local exit_code="$1" title body payload
  title="Codex App-Server Update Failed"
  body="The scheduled Codex app-server update failed on $(hostname) during ${CURRENT_STAGE}. Exit code: ${exit_code}. Time: $(date -Is). Log: ${LOG_FILE}"
  payload="$(APPRISE_TITLE="$title" APPRISE_BODY="$body" python3 -c \
    'import json, os; print(json.dumps({"title": os.environ["APPRISE_TITLE"], "body": os.environ["APPRISE_BODY"], "type": "failure"}))')" || {
    echo "Failed to build the Apprise failure notification payload"
    return 1
  }

  if curl --noproxy '*' --fail-with-body --silent --show-error --insecure \
    --max-time 20 --retry 2 --retry-all-errors \
    -X POST "$APPRISE_NOTIFY_URL" \
    -H 'Content-Type: application/json' \
    --data "$payload" >/dev/null; then
    echo "Sent Codex app-server update failure notification through Apprise"
    return 0
  fi

  echo "Failed to send Codex app-server update failure notification through Apprise"
  return 1
}

notify_on_exit() {
  local exit_code=$?
  trap - EXIT
  if [ "$exit_code" -ne 0 ]; then
    send_failure_notification "$exit_code" || true
  fi
  exit "$exit_code"
}

trap notify_on_exit EXIT

codex_update_with_fallback() {
  local tmp rc before after
  tmp="$(mktemp)"
  before="$(codex --version 2>&1 || true)"
  echo "host=$(hostname) before=$before"
  local before_ver
  before_ver="$(printf '%s\n' "$before" | sed -n 's/^codex-cli //p' | head -n1)"

  echo "Trying codex update with proxy $CODEX_PROXY_URL"
  http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" codex update 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
    rc=1
  fi

  if [ "$rc" -ne 0 ] && [ -n "$before_ver" ] \
    && grep -Fq "Could not find Codex package or platform npm release assets for Codex $before_ver" "$tmp"; then
    echo "Proxy update attempt reported missing assets for already-installed Codex $before_ver; not retrying without proxy"
  elif [ "$rc" -ne 0 ]; then
    echo "Proxy update attempt failed or looked unhealthy (exit $rc); retrying without proxy"
    # Replace the failed proxy attempt output. Appending here makes the
    # health check below rediscover the first attempt's curl error and report
    # a false failure even when the direct retry succeeds.
    codex update 2>&1 | tee "$tmp"
    rc=${PIPESTATUS[0]}
    if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
      rc=1
    fi
    if [ "$rc" -ne 0 ]; then
      echo "Direct retry also failed or looked unhealthy; retrying through proxy once more"
      sleep 3
      http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" codex update 2>&1 | tee "$tmp"
      rc=${PIPESTATUS[0]}
      if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
        rc=1
      fi
    fi
  fi

  after="$(codex --version 2>&1 || true)"
  echo "host=$(hostname) after=$after"

  # Some current Codex builds can return non-zero while re-installing the
  # already-installed version. Treat that as a no-op success only when the
  # installed version is unchanged and the reported missing asset is for that
  # same version.
  local after_ver
  after_ver="$(printf '%s\n' "$after" | sed -n 's/^codex-cli //p' | head -n1)"
  if [ "$rc" -ne 0 ] && [ -n "$before_ver" ] && [ "$before_ver" = "$after_ver" ] \
    && grep -Fq "Could not find Codex package or platform npm release assets for Codex $after_ver" "$tmp"; then
    echo "Update command reported missing assets for already-installed Codex $after_ver; treating as no-op success"
    rc=0
  fi

  rm -f "$tmp"
  return "$rc"
}

restart_codex_app_server_if_managed() {
  if ! codex app-server daemon version >/dev/null 2>&1; then
    echo "No managed codex app-server daemon detected; skipping restart"
    return 0
  fi

  echo "Restarting codex app-server daemon with proxy $CODEX_PROXY_URL to pick up updated Codex"
  local restart_output rc
  restart_output="$(HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    timeout 300 codex app-server daemon restart 2>&1)"
  rc=$?
  printf '%s\n' "$restart_output"
  if [ "$rc" -eq 0 ]; then
    echo "app-server version after restart:"
    codex app-server daemon version || true
    return 0
  fi

  # The local Codex Desktop can own an app-server that is intentionally not
  # managed by `codex app-server daemon`. Updating the standalone Codex is
  # still successful in that case; do not turn it into a cron failure.
  if printf '%s\n' "$restart_output" | grep -Fq 'is running but is not managed by codex app-server daemon'; then
    echo "Codex app-server is owned by another local client; skipping daemon restart"
    return 0
  fi

  echo "codex app-server daemon restart failed"
  return 1
}

{
  echo "===== $(date -Is) codex update run starting on $(hostname) ====="

  # Load SSH key for non-interactive cron runs. --noask prevents passphrase prompts.
  if command -v keychain >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
  fi

  overall_rc=0

  CURRENT_STAGE="dev update and app-server recovery"
  echo "=== Updating dev first ==="
  if ! timeout 900 ssh dev 'bash -s' <<'REMOTE_DEV_UPDATE'
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CODEX_PROXY_URL="http://proxy.skynet:10810"
codex_update_with_fallback() {
  local tmp rc before after
  tmp="$(mktemp)"
  before="$(codex --version 2>&1 || true)"
  echo "host=$(hostname) before=$before"
  local before_ver
  before_ver="$(printf '%s\n' "$before" | sed -n 's/^codex-cli //p' | head -n1)"

  echo "Trying codex update with proxy $CODEX_PROXY_URL"
  http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" codex update 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
    rc=1
  fi

  if [ "$rc" -ne 0 ] && [ -n "$before_ver" ] \
    && grep -Fq "Could not find Codex package or platform npm release assets for Codex $before_ver" "$tmp"; then
    echo "Proxy update attempt reported missing assets for already-installed Codex $before_ver; not retrying without proxy"
  elif [ "$rc" -ne 0 ]; then
    echo "Proxy update attempt failed or looked unhealthy (exit $rc); retrying without proxy"
    # Replace the failed proxy attempt output so a successful direct retry is
    # not marked unhealthy by stale curl errors from the first attempt.
    codex update 2>&1 | tee "$tmp"
    rc=${PIPESTATUS[0]}
    if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
      rc=1
    fi
    if [ "$rc" -ne 0 ]; then
      echo "Direct retry also failed or looked unhealthy; retrying through proxy once more"
      sleep 3
      http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" codex update 2>&1 | tee "$tmp"
      rc=${PIPESTATUS[0]}
      if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
        rc=1
      fi
    fi
  fi

  after="$(codex --version 2>&1 || true)"
  echo "host=$(hostname) after=$after"

  # Some current Codex builds can return non-zero while re-installing the
  # already-installed version. Treat that as a no-op success only when the
  # installed version is unchanged and the reported missing asset is for that
  # same version.
  local after_ver
  after_ver="$(printf '%s\n' "$after" | sed -n 's/^codex-cli //p' | head -n1)"
  if [ "$rc" -ne 0 ] && [ -n "$before_ver" ] && [ "$before_ver" = "$after_ver" ] \
    && grep -Fq "Could not find Codex package or platform npm release assets for Codex $after_ver" "$tmp"; then
    echo "Update command reported missing assets for already-installed Codex $after_ver; treating as no-op success"
    rc=0
  fi

  rm -f "$tmp"
  return "$rc"
}
codex_daemon_updater_alive() {
  local updater_pid_file updater_pid
  updater_pid_file="$HOME/.codex/app-server-daemon/app-server-updater.pid"
  [ -r "$updater_pid_file" ] || return 1
  updater_pid="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$updater_pid_file" | head -n1)"
  [ -n "$updater_pid" ] && kill -0 "$updater_pid" 2>/dev/null
}

verify_codex_app_server_dev() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if codex app-server daemon version >/dev/null 2>&1 && codex_daemon_updater_alive; then
      return 0
    fi
    sleep 2
  done
  return 1
}

restart_or_bootstrap_codex_app_server_dev() {
  local restart_output rc

  if codex app-server daemon version >/dev/null 2>&1; then
    echo "Restarting managed dev Codex app-server with proxy $CODEX_PROXY_URL"
    restart_output="$(HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
      http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
      timeout 300 codex app-server daemon restart 2>&1)"
    rc=$?
    printf '%s\n' "$restart_output"
    if [ "$rc" -eq 124 ]; then
      echo "Managed dev Codex app-server restart timed out while waiting for active turns"
      return 1
    fi
    if [ "$rc" -eq 0 ] && verify_codex_app_server_dev; then
      echo "Managed dev Codex app-server and updater are healthy after restart"
      codex app-server daemon version
      return 0
    fi
    echo "Managed restart did not restore both app-server and updater; bootstrapping durable management"
  else
    echo "No healthy managed dev Codex app-server detected; bootstrapping durable management"
  fi

  if ! HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    codex app-server daemon bootstrap --remote-control; then
    echo "codex app-server daemon bootstrap failed"
    return 1
  fi

  if ! verify_codex_app_server_dev; then
    echo "codex app-server or its durable updater is still unhealthy after bootstrap"
    return 1
  fi

  echo "Durable dev Codex app-server is healthy after bootstrap"
  codex app-server daemon version
  return 0
}

# Scope: update the standalone Codex/app-server installation only. MyAgents
# dependencies and processes are intentionally outside this cron task.
codex_update_with_fallback && restart_or_bootstrap_codex_app_server_dev
REMOTE_DEV_UPDATE
  then
    overall_rc=1
    echo "=== dev update failed; skipping lab update to preserve requested order ==="
    echo "===== $(date -Is) codex update run finished with failure ====="
    exit "$overall_rc"
  fi

  CURRENT_STAGE="lab update and app-server restart"
  echo "=== Updating lab second ==="
  if codex_update_with_fallback; then
    if ! restart_codex_app_server_if_managed; then
      overall_rc=1
    fi
  else
    overall_rc=1
  fi

  if [ "$overall_rc" -eq 0 ]; then
    CURRENT_STAGE="completed"
    echo "===== $(date -Is) codex update run finished successfully ====="
  else
    echo "===== $(date -Is) codex update run finished with failure rc=$overall_rc ====="
  fi
  exit "$overall_rc"
} >>"$LOG_FILE" 2>&1
