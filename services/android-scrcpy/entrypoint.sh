#!/usr/bin/env bash
set -euo pipefail

mode="${1:-desktop}"

case "$mode" in
  adb-server)
    install -d -m 0700 "$HOME/.android"
    exec adb -a nodaemon server
    ;;

  desktop)
    vnc_password_file="${VNC_PASSWORD_FILE:-/run/secrets/vnc_password}"
    vnc_geometry="${VNC_GEOMETRY:-540x1120}"
    vnc_port="${VNC_PORT:-5900}"
    novnc_port="${NOVNC_PORT:-6080}"
    adb_serial="${ADB_SERIAL:-9c9c03f}"

    if [[ ! -r "$vnc_password_file" ]]; then
      echo "VNC password file is missing or unreadable: $vnc_password_file" >&2
      exit 1
    fi

    if [[ "$(tr -d '\r\n' <"$vnc_password_file" | wc -c)" -lt 6 ]]; then
      echo "VNC password must contain at least 6 characters" >&2
      exit 1
    fi

    printf '%s\n' "$(tr -d '\r\n' <"$vnc_password_file")" \
      | tigervncpasswd -f > /run/vncpasswd
    chmod 0600 /run/vncpasswd

    vnc_pid=""
    openbox_pid=""
    websockify_pid=""

    cleanup() {
      trap - EXIT INT TERM
      for pid in "$websockify_pid" "$openbox_pid" "$vnc_pid"; do
        if [[ -n "$pid" ]]; then
          kill "$pid" 2>/dev/null || true
        fi
      done
      wait 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    Xtigervnc "$DISPLAY" \
      -geometry "$vnc_geometry" \
      -depth 24 \
      -rfbport "$vnc_port" \
      -localhost yes \
      -SecurityTypes VncAuth \
      -PasswordFile /run/vncpasswd \
      -AlwaysShared \
      -DisconnectClients=0 \
      -AcceptSetDesktopSize=0 \
      -desktop "Android scrcpy" &
    vnc_pid="$!"

    for _ in $(seq 1 100); do
      if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    xdpyinfo -display "$DISPLAY" >/dev/null

    openbox >/tmp/openbox.log 2>&1 &
    openbox_pid="$!"

    websockify \
      --web=/usr/share/novnc \
      --heartbeat=30 \
      "0.0.0.0:${novnc_port}" \
      "127.0.0.1:${vnc_port}" &
    websockify_pid="$!"

    for _ in $(seq 1 60); do
      if adb -s "$adb_serial" get-state 2>/dev/null | grep -qx device; then
        break
      fi
      sleep 1
    done

    if ! adb -s "$adb_serial" get-state 2>/dev/null | grep -qx device; then
      echo "ADB device is not ready or authorized: $adb_serial" >&2
      adb devices -l >&2 || true
      exit 1
    fi

    tunnel_host="$(getent ahostsv4 android-adb | awk 'NR == 1 { print $1 }')"
    if [[ -z "$tunnel_host" ]]; then
      echo "Could not resolve android-adb to an IPv4 address" >&2
      exit 1
    fi

    scrcpy \
      --serial="$adb_serial" \
      --tunnel-host="$tunnel_host" \
      --max-size="${SCRCPY_MAX_SIZE:-1080}" \
      --max-fps="${SCRCPY_MAX_FPS:-30}" \
      --video-bit-rate="${SCRCPY_VIDEO_BIT_RATE:-6M}" \
      --no-audio \
      --stay-awake \
      --fullscreen \
      --window-borderless \
      --window-title="Android" &

    scrcpy_pid="$!"
    printf '%s\n' "$scrcpy_pid" > /run/scrcpy.pid

    # The static scrcpy launcher may leave Bash's job bookkeeping waiting even
    # after its process disappears. Poll its PID instead so an ADB loss always
    # reaches the EXIT trap and lets Docker restart the complete desktop.
    while kill -0 "$scrcpy_pid" 2>/dev/null; do
      sleep 1
    done
    exit 1
    ;;

  *)
    exec "$@"
    ;;
esac
