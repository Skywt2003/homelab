# Dashy

This stack runs Dashy for `index.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Dashy's service index is maintained in `conf.yml`.

Custom static assets are stored in `assets/` and mounted into Dashy's Web UI.
The `web-icons/` assets also replace Dashy's default PWA and Safari home-screen icons.

## Deploy

```bash
cd ~/homelab/hosts/lab/dashy
sudo docker compose -f compose.yml up -d
```
