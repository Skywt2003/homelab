# Portainer

Portainer CE provides a web UI for managing the Docker Engine on `lab`.

- URL: `https://containers.lab.skywt`
- Image: `portainer/portainer-ce:2.39.2`
- Caddy upstream: Portainer's internal HTTP listener on port `9000`
- Runtime data: `/data/homelab/lab/portainer/data`

Caddy terminates HTTPS with the lab internal CA. Portainer's ports, including
the Edge Agent tunnel port (`8000`), are not published on the host.

Portainer requires write access to `/var/run/docker.sock` to manage the local
Docker Engine. Treat Portainer administrator access as root-equivalent access
to `lab` and keep this service restricted to the trusted lab network.

The container health check uses Portainer's bundled Docker CLI to verify that
the mounted socket is usable and the local Docker Engine responds. The image is
minimal and does not include `curl` or `wget` for an HTTP-based check.

## Deploy

```bash
sudo install -d -m 0700 -o root -g root /data/homelab/lab/portainer/data
cd ~/homelab/services/portainer
sudo docker compose -f compose.yml up -d
```

On the first visit, create the initial administrator account and select the
local Docker environment. Portainer disables the first-run setup page after a
short inactivity timeout; restart the container if the page reports that the
instance timed out.

## Verify

```bash
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-portainer
curl -I https://containers.lab.skywt
```
