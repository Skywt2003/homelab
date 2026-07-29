#!/bin/sh

set -eu

action=${1:-}

case "$action" in
  pause)
    paused=true
    ;;
  resume)
    paused=false
    ;;
  *)
    echo '{"status":"error","message":"invalid action"}' >&2
    exit 2
    ;;
esac

api_key=$(cat /run/secrets/immich_api_key)
queues="smartSearch faceDetection facialRecognition ocr"

for queue in $queues; do
  curl --noproxy '*' --fail --silent --show-error \
    --connect-timeout 5 --max-time 30 \
    --request PUT \
    --header "x-api-key: $api_key" \
    --header 'Content-Type: application/json' \
    --data "{\"isPaused\":$paused}" \
    "http://immich-server:2283/api/queues/$queue" >/dev/null
done

unset api_key

printf '{"status":"ok","action":"%s","queues":["smartSearch","faceDetection","facialRecognition","ocr"]}\n' \
  "$action"
