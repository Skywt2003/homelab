# RSSHub

This stack runs RSSHub for `rsshub.lab.skywt`.

The Web UI and routes are exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Redis is used as RSSHub's cache backend. Browserless Chromium provides Playwright rendering for routes that need a browser.

Only the RSSHub container joins the shared `lab-proxy` network. Redis and Browserless Chromium stay on the stack-local `rsshub-internal` network.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/rsshub/redis`

Public, non-secret environment configuration is stored outside Git:

- `/data/homelab/lab/rsshub/env/public.env`

## Secrets

`TWITTER_AUTH_TOKEN` is managed in Infisical path `/rsshub` and materialized to:

- `/run/homelab/secrets/rsshub/twitter_auth_token`

The RSSHub image expects the token as an environment variable, so Compose mounts it as a Docker secret and uses a shell wrapper to export `TWITTER_AUTH_TOKEN` immediately before `exec npm run start`.

Do not add route credentials, cookies, tokens, or account secrets to Git-maintained files or the public env file.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/rsshub/{env,redis}
cd ~/homelab
sudo ./scripts/materialize-secrets.sh rsshub
cd ~/homelab/services/rsshub
sudo docker compose -f compose.yml up -d
```
