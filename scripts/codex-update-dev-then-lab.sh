#!/usr/bin/env bash
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG_DIR="/home/skywt/homelab/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/codex-update.log"
CODEX_PROXY_URL="http://proxy:10810"

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
    codex update 2>&1 | tee -a "$tmp"
    rc=${PIPESTATUS[0]}
    if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
      rc=1
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
  if HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    codex app-server daemon restart; then
    echo "app-server version after restart:"
    codex app-server daemon version || true
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

  echo "=== Updating dev first ==="
  if ! ssh dev 'bash -s' <<'REMOTE_DEV_UPDATE'
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CODEX_PROXY_URL="http://proxy:10810"
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
    codex update 2>&1 | tee -a "$tmp"
    rc=${PIPESTATUS[0]}
    if grep -Eq 'curl: \([0-9]+\)|Failed to connect|Could not connect|Could not resolve|timed out|Connection refused' "$tmp"; then
      rc=1
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
  if HTTP_PROXY="$CODEX_PROXY_URL" HTTPS_PROXY="$CODEX_PROXY_URL" \
    http_proxy="$CODEX_PROXY_URL" https_proxy="$CODEX_PROXY_URL" \
    codex app-server daemon restart; then
    echo "app-server version after restart:"
    codex app-server daemon version || true
    return 0
  fi

  echo "codex app-server daemon restart failed"
  return 1
}

codex_update_with_fallback && restart_codex_app_server_if_managed
REMOTE_DEV_UPDATE
  then
    overall_rc=1
    echo "=== dev update failed; skipping lab update to preserve requested order ==="
    echo "===== $(date -Is) codex update run finished with failure ====="
    exit "$overall_rc"
  fi

  echo "=== Updating lab second ==="
  if codex_update_with_fallback; then
    if ! restart_codex_app_server_if_managed; then
      overall_rc=1
    fi
  else
    overall_rc=1
  fi

  if [ "$overall_rc" -eq 0 ]; then
    echo "===== $(date -Is) codex update run finished successfully ====="
  else
    echo "===== $(date -Is) codex update run finished with failure rc=$overall_rc ====="
  fi
  exit "$overall_rc"
} >>"$LOG_FILE" 2>&1
