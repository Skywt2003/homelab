#!/bin/sh

set -eu

token=$(cat /run/secrets/webhook_token)

case "$token" in
  ''|*[!A-Za-z0-9_-]*)
    echo "webhook token must contain only letters, digits, underscores, or hyphens" >&2
    exit 1
    ;;
esac

sed "s/__WEBHOOK_TOKEN__/$token/g" \
  /etc/webhook/hooks.json.template > /tmp/hooks.json

unset token

exec /usr/local/bin/webhook "$@"
