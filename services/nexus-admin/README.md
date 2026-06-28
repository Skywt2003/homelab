# Nexus Admin

Nexus Admin is the administration UI for the Nexus/blog application.

- Domain: `https://blog-admin.lab.skywt`
- Image: `docker.lab.skywt/nexus-admin:2606281529`
- Container: `lab-nexus-admin`
- Upstream port: `3000`
- Reverse proxy: shared Caddy stack via Docker labels on the external `lab-proxy` network.
- Environment: `services/nexus-admin/.env`, copied from `dev:/home/skywt/Codes/nexus-admin/.env` and intentionally not committed.
- TLS trust: mounts the lab host CA bundle and sets `NODE_EXTRA_CA_CERTS` so Node can validate outbound HTTPS services.

## Deploy

```bash
cd ~/homelab/services/nexus-admin
sudo docker compose -f compose.yml up -d
```

## Verify

```bash
cd ~/homelab/services/nexus-admin
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-nexus-admin
curl --noproxy '*' --resolve blog-admin.lab.skywt:443:127.0.0.1 -k -I https://blog-admin.lab.skywt/
```
