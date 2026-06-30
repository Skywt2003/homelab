# Apprise API

Apprise API is the local notification gateway for `notify.lab.skywt`.
It exposes the Apprise notification library through a REST API and small web UI, so local services can send notifications to configured targets such as Email, Bark, Telegram, Feishu/Lark, ntfy, Gotify, Discord, Slack, and many others.

## Domain

- URL: `https://notify.lab.skywt`
- Caddy route: Docker labels in `compose.yml`
- Upstream port: `8000`
- TLS: Caddy internal CA

## Runtime Data

Mutable state lives on the `lab` host under:

- `/data/homelab/lab/apprise-api/config` - saved Apprise API configuration and state
- `/data/homelab/lab/apprise-api/attach` - uploaded attachments
- `/data/homelab/lab/apprise-api/plugin` - optional custom Apprise plugins

Prepare the directories before first deploy:

```bash
sudo mkdir -p /data/homelab/lab/apprise-api/{config,attach,plugin}
sudo chown -R 1000:1000 /data/homelab/lab/apprise-api
```

## Deploy

```bash
cd ~/homelab/services/apprise-api
sudo docker compose -f compose.yml up -d
```

## Validate

```bash
cd ~/homelab/services/apprise-api
docker compose -f compose.yml config
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-apprise-api
```

Health check endpoint:

```bash
curl -k https://notify.lab.skywt/status
```

Expected plain-text response is `OK` when the service can read and write its configured paths.
