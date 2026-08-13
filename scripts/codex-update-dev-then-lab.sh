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
# A manual run from an active Codex Desktop task may update the lab CLI without
# restarting the app-server that owns the current conversation.
SKIP_LAB_APP_SERVER_RESTART="${SKIP_LAB_APP_SERVER_RESTART:-0}"
CODEX_VERSION_CHANGED=0

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
  if [ -n "$before_ver" ] && [ -n "$after_ver" ] && [ "$before_ver" != "$after_ver" ]; then
    CODEX_VERSION_CHANGED=1
  else
    CODEX_VERSION_CHANGED=0
  fi
  if [ "$rc" -ne 0 ] && [ -n "$before_ver" ] && [ "$before_ver" = "$after_ver" ] \
    && grep -Fq "Could not find Codex package or platform npm release assets for Codex $after_ver" "$tmp"; then
    echo "Update command reported missing assets for already-installed Codex $after_ver; treating as no-op success"
    rc=0
  fi

  rm -f "$tmp"
  return "$rc"
}

local_pid_from_codex_file() {
  local pid_file="$1"
  [ -r "$pid_file" ] || return 1
  sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$pid_file" | head -n1
}

local_pid_state() {
  local pid="$1"
  [ -r "/proc/$pid/stat" ] || return 1
  awk '{ print $3 }' "/proc/$pid/stat"
}

local_codex_daemon_healthy() {
  local daemon_dir server_pid updater_pid server_state updater_state
  daemon_dir="$HOME/.codex/app-server-daemon"
  server_pid="$(local_pid_from_codex_file "$daemon_dir/app-server.pid" || true)"
  updater_pid="$(local_pid_from_codex_file "$daemon_dir/app-server-updater.pid" || true)"
  [ -n "$server_pid" ] && [ -n "$updater_pid" ] || return 1
  server_state="$(local_pid_state "$server_pid" || true)"
  updater_state="$(local_pid_state "$updater_pid" || true)"
  [ -n "$server_state" ] && [ "$server_state" != "Z" ] \
    && [ -n "$updater_state" ] && [ "$updater_state" != "Z" ] \
    && codex app-server daemon version >/dev/null 2>&1
}

recover_local_zombie_codex_daemon() {
  local daemon_dir server_pid updater_pid state attempt
  daemon_dir="$HOME/.codex/app-server-daemon"
  server_pid="$(local_pid_from_codex_file "$daemon_dir/app-server.pid" || true)"
  [ -n "$server_pid" ] || return 1
  state="$(local_pid_state "$server_pid" || true)"
  [ "$state" = "Z" ] || return 1

  echo "Detected zombie local managed Codex app-server pid $server_pid; stopping its updater parent"
  updater_pid="$(local_pid_from_codex_file "$daemon_dir/app-server-updater.pid" || true)"
  if [ -n "$updater_pid" ] && kill -0 "$updater_pid" 2>/dev/null; then
    kill -TERM "$updater_pid" 2>/dev/null || true
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$updater_pid" 2>/dev/null || break
      sleep 1
    done
    kill -0 "$updater_pid" 2>/dev/null && kill -KILL "$updater_pid" 2>/dev/null || true
  fi
  for attempt in 1 2 3 4 5; do
    [ ! -e "/proc/$server_pid" ] && break
    sleep 1
  done
  [ ! -e "/proc/$server_pid" ] || return 1
  rm -f "$daemon_dir/app-server.pid" "$daemon_dir/app-server-updater.pid"
  echo "Cleared stale local Codex daemon PID files after zombie recovery"
  return 0
}

bootstrap_local_codex_daemon() {
  local rc attempt
  rc=0
  HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    codex app-server daemon bootstrap --remote-control || rc=$?
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if local_codex_daemon_healthy; then
      [ "$rc" -eq 0 ] || echo "Bootstrap returned $rc during readiness, but the local daemon is now healthy"
      codex app-server daemon version
      return 0
    fi
    sleep 2
  done
  echo "Local Codex daemon is still unhealthy after bootstrap (exit $rc)"
  return 1
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

  if recover_local_zombie_codex_daemon; then
    echo "Recovered zombie local app-server after failed restart; bootstrapping durable management"
    if bootstrap_local_codex_daemon; then
      return 0
    fi
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
CODEX_VERSION_CHANGED=0
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
  if [ -n "$before_ver" ] && [ -n "$after_ver" ] && [ "$before_ver" != "$after_ver" ]; then
    CODEX_VERSION_CHANGED=1
  else
    CODEX_VERSION_CHANGED=0
  fi
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

codex_managed_app_server_alive() {
  local server_pid state
  server_pid="$(pid_from_codex_file "$HOME/.codex/app-server-daemon/app-server.pid" || true)"
  [ -n "$server_pid" ] || return 1
  state="$(pid_state "$server_pid" || true)"
  [ -n "$state" ] && [ "$state" != "Z" ] && kill -0 "$server_pid" 2>/dev/null
}

codex_managed_daemon_healthy() {
  codex_managed_app_server_alive \
    && codex_daemon_updater_alive \
    && codex app-server daemon version >/dev/null 2>&1
}

pid_state() {
  local pid="$1"
  [ -r "/proc/$pid/stat" ] || return 1
  awk '{ print $3 }' "/proc/$pid/stat"
}

pid_from_codex_file() {
  local pid_file="$1"
  [ -r "$pid_file" ] || return 1
  sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$pid_file" | head -n1
}

recover_zombie_codex_daemon() {
  local daemon_dir server_pid updater_pid state attempt
  daemon_dir="$HOME/.codex/app-server-daemon"
  server_pid="$(pid_from_codex_file "$daemon_dir/app-server.pid" || true)"
  [ -n "$server_pid" ] || return 1
  state="$(pid_state "$server_pid" || true)"
  [ "$state" = "Z" ] || return 1

  echo "Detected zombie managed Codex app-server pid $server_pid; stopping its updater parent"
  updater_pid="$(pid_from_codex_file "$daemon_dir/app-server-updater.pid" || true)"
  if [ -n "$updater_pid" ] && kill -0 "$updater_pid" 2>/dev/null; then
    kill -TERM "$updater_pid" 2>/dev/null || true
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$updater_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$updater_pid" 2>/dev/null; then
      echo "Updater pid $updater_pid did not stop after SIGTERM; sending SIGKILL"
      kill -KILL "$updater_pid" 2>/dev/null || true
    fi
  fi

  for attempt in 1 2 3 4 5; do
    [ ! -e "/proc/$server_pid" ] && break
    sleep 1
  done
  if [ -e "/proc/$server_pid" ]; then
    echo "Zombie managed app-server pid $server_pid was not reaped"
    return 1
  fi

  rm -f "$daemon_dir/app-server.pid" "$daemon_dir/app-server-updater.pid"
  echo "Cleared stale Codex daemon PID files after zombie recovery"
  return 0
}

stop_unmanaged_codex_control_server() {
  local socket_path owner_pid owner_exe owner_cmd attempt
  socket_path="$HOME/.codex/app-server-control/app-server-control.sock"
  owner_pid="$(ss -xlpn 2>/dev/null | sed -n "s#.*${socket_path}.*pid=\([0-9][0-9]*\).*#\1#p" | head -n1)"
  [ -n "$owner_pid" ] || return 0

  owner_exe="$(readlink -f "/proc/$owner_pid/exe" 2>/dev/null || true)"
  owner_cmd="$(tr '\0' ' ' < "/proc/$owner_pid/cmdline" 2>/dev/null || true)"
  case "$owner_exe:$owner_cmd" in
    "$HOME"/.codex/packages/standalone/releases/*/bin/codex:*app-server*) ;;
    *)
      echo "Refusing to stop unexpected Codex control socket owner pid $owner_pid: $owner_exe $owner_cmd"
      return 1
      ;;
  esac

  echo "Stopping standalone non-managed Codex control server pid $owner_pid before bootstrap"
  kill -TERM "$owner_pid" 2>/dev/null || true
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    kill -0 "$owner_pid" 2>/dev/null || return 0
    sleep 1
  done
  echo "Non-managed Codex control server pid $owner_pid did not stop after SIGTERM"
  return 1
}

verify_codex_app_server_dev() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if codex_managed_daemon_healthy; then
      return 0
    fi
    sleep 2
  done
  return 1
}

restart_or_bootstrap_codex_app_server_dev() {
  local restart_output rc recovered_zombie bootstrap_rc
  recovered_zombie=0

  # Codex 0.146.1 can leave its managed app-server as a zombie whose updater
  # parent never calls wait(2). The daemon's normal restart then waits forever
  # because the zombie PID still exists. Reap that stale process tree first.
  if recover_zombie_codex_daemon; then
    recovered_zombie=1
  fi

  if [ "$recovered_zombie" -eq 1 ]; then
    stop_unmanaged_codex_control_server || return 1
  fi

  if codex_managed_daemon_healthy; then
    if [ "$CODEX_VERSION_CHANGED" -eq 0 ]; then
      echo "Codex version is unchanged and the managed dev app-server is healthy; skipping restart"
      codex app-server daemon version
      return 0
    fi
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
    if recover_zombie_codex_daemon; then
      stop_unmanaged_codex_control_server || return 1
    fi
  else
    echo "No healthy managed dev Codex app-server detected; bootstrapping durable management"
    stop_unmanaged_codex_control_server || return 1
  fi

  bootstrap_rc=0
  HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    codex app-server daemon bootstrap --remote-control || bootstrap_rc=$?

  if ! verify_codex_app_server_dev; then
    [ "$bootstrap_rc" -eq 0 ] || echo "codex app-server daemon bootstrap failed with exit $bootstrap_rc"
    echo "codex app-server or its durable updater is still unhealthy after bootstrap"
    return 1
  fi

  if [ "$bootstrap_rc" -ne 0 ]; then
    echo "Bootstrap returned $bootstrap_rc during readiness, but the durable dev daemon is now healthy"
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
    if [ "$SKIP_LAB_APP_SERVER_RESTART" = "1" ]; then
      echo "Skipping lab app-server restart because SKIP_LAB_APP_SERVER_RESTART=1"
    elif [ "$CODEX_VERSION_CHANGED" -eq 0 ]; then
      echo "Codex version is unchanged; skipping lab app-server restart"
    elif ! restart_codex_app_server_if_managed; then
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
