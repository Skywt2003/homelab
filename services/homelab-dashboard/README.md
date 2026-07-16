# HomeLab Dashboard

HomeLab Dashboard is a minimal Docker-label-powered service index for the lab host.

- Domain: `https://dashboard.lab.skywt`
- Image: `docker.lab.skywt/homelab-dashboard:latest`
- Upstream port: `3000`
- Caddy exposure: Docker labels on the `homelab-dashboard` service route `dashboard.lab.skywt` through the shared `lab-proxy` network.
- Runtime data: none.
- Secrets: none.

## Docker labels

The dashboard reads Docker container labels through the read-only Docker socket mount at `/var/run/docker.sock`.
The stack adds supplementary group `989`, matching the current `lab` host Docker socket group inside containers, so the image's `nextjs` user can read the socket without running the app as root.

The image defaults to the `labdash` label prefix. This stack also sets `LABDASH_LABEL_PREFIX=labdash` explicitly.

Supported labels observed from the deployed image:

- `labdash.enable`: must be `"true"` for the container to appear.
- `labdash.name`: short display name.
- `labdash.appname`: application display name.
- `labdash.url`: optional HTTPS URL for clickable entries.
- `labdash.icon`: optional Tabler icon name.
- `labdash.group`: dashboard section.
- `labdash.order`: numeric sort order within a section.

## Deploy

```bash
cd ~/homelab/services/homelab-dashboard
sudo docker compose -f compose.yml config
sudo docker compose -f compose.yml up -d
```

## Verify

```bash
cd ~/homelab/services/homelab-dashboard
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-homelab-dashboard
sudo docker exec lab-caddy wget -S -O- --no-check-certificate --header 'Host: dashboard.lab.skywt' https://127.0.0.1
```
