#!/bin/sh
set -eu

secret_file="/run/secrets/secret_key"
template_file="${CRONICLE_CONFIG_TEMPLATE:-/etc/cronicle/config.template.json}"
setup_marker="/opt/cronicle/data/.homelab-setup-complete"

if [ ! -r "$secret_file" ]; then
  echo "missing Cronicle secret key at $secret_file" >&2
  exit 1
fi

if [ ! -r "$template_file" ]; then
  echo "missing Cronicle config template at $template_file" >&2
  exit 1
fi

mkdir -p /opt/cronicle/conf /opt/cronicle/data /opt/cronicle/logs /opt/cronicle/queue

node <<'JS'
const fs = require('fs');
const secret = fs.readFileSync('/run/secrets/secret_key', 'utf8').trim();
const templatePath = process.env.CRONICLE_CONFIG_TEMPLATE || '/etc/cronicle/config.template.json';
const configPath = '/opt/cronicle/conf/config.json';
const config = JSON.parse(fs.readFileSync(templatePath, 'utf8'));
config.secret_key = secret;
config.base_app_url = process.env.CRONICLE_BASE_APP_URL || config.base_app_url || 'https://cron.lab.skywt';
config.email_from = process.env.CRONICLE_EMAIL_FROM || config.email_from || 'cronicle@lab.skywt';
config.smtp_hostname = process.env.CRONICLE_SMTP_HOSTNAME || config.smtp_hostname || 'localhost';
config.smtp_port = Number(process.env.CRONICLE_SMTP_PORT || config.smtp_port || 25);
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
JS

if [ ! -f "$setup_marker" ]; then
  echo "initializing Cronicle filesystem storage"
  node /opt/cronicle/bin/storage-cli.js setup
  touch "$setup_marker"
fi

exec "$@"
