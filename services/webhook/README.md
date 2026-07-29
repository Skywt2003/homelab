# Webhook Gateway

`adnanh/webhook` is available inside the homelab at
`https://webhook.lab.skywt` through the shared Caddy proxy.

Apple Home hubs that do not use the homelab DNS resolver can use the equivalent
LAN-IP endpoint `https://192.168.1.236`. Caddy issues that IP address a
certificate from the same internal CA. The DHCP server must keep
`192.168.1.236` reserved for `lab`.

The image is built from the upstream `adnanh/webhook` Linux release artifact
for version `2.8.3`. The release archive is pinned by SHA-256 during the image
build. The service runs as an unprivileged user with a read-only root
filesystem and does not have access to the Docker socket.

## Immich machine-learning hooks

The gateway exposes two authenticated endpoints:

```text
POST https://webhook.lab.skywt/hooks/immich-home
POST https://webhook.lab.skywt/hooks/immich-away
```

For Apple Home, use:

```text
POST https://192.168.1.236/hooks/immich-home
POST https://192.168.1.236/hooks/immich-away
```

Both requests must include the header:

```text
X-Webhook-Token: <token>
```

`immich-home` pauses these Immich queues:

- Smart Search
- Face Detection
- Facial Recognition
- OCR

`immich-away` resumes the same queues. Commands use Immich's queue API rather
than pausing the machine-learning container.

The webhook token and Immich API key are materialized as root-only files:

```text
/run/homelab/secrets/webhook/webhook_token
/run/homelab/secrets/webhook/immich_api_key
```

Their Infisical source-of-truth names are `WEBHOOK_TOKEN` and
`WEBHOOK_IMMICH_API_KEY` in the project root path. Materialize them with:

```bash
sudo ./scripts/materialize-secrets.sh webhook
```

Retrieve the token for Apple Home configuration with:

```bash
sudo cat /run/homelab/secrets/webhook/webhook_token
```

## Deploy

```bash
cd ~/homelab/services/webhook
sudo docker compose -f compose.yml config
sudo docker compose -f compose.yml up -d --build
```

## Verify

An unauthenticated request must return `401`. An authenticated request can be
tested with:

```bash
TOKEN=$(sudo cat /run/homelab/secrets/webhook/webhook_token)
curl --cacert /tmp/caddy-local-root.crt \
  -H "X-Webhook-Token: $TOKEN" \
  -X POST \
  https://webhook.lab.skywt/hooks/immich-home
```

Inspect hook execution with:

```bash
sudo docker logs --follow lab-webhook
```
