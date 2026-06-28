# RSSHub

This stack runs RSSHub for `rsshub.lab.skywt`.

The Web UI and routes are exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Redis is used as RSSHub's cache backend. Browserless Chromium provides Playwright rendering for routes that need a browser.

Only the RSSHub container joins the shared `lab-proxy` network. Redis and Browserless Chromium stay on the stack-local `rsshub-internal` network.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/rsshub/redis`

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/rsshub/redis
cd ~/homelab/services/rsshub
sudo docker compose -f compose.yml up -d
```
