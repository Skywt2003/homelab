# Nexus Admin

Nexus Admin is the administration UI for the Nexus/blog application.

- Domain: `https://blog-admin.lab.skywt`
- Image: `docker.lab.skywt/nexus-admin:2606281529`
- Container: `lab-nexus-admin`
- Upstream port: `3000`
- Reverse proxy: shared Caddy stack via Docker labels on the external `lab-proxy` network.
- Public environment: `/data/homelab/lab/nexus-admin/env/public.env` on the lab host.
- TLS trust: mounts the lab host CA bundle and sets `NODE_EXTRA_CA_CERTS` so Node can validate outbound HTTPS services.

## Secrets

Secret values are managed in Infisical path `/nexus-admin` and materialized under:

- `/run/homelab/secrets/nexus-admin/admin_password`
- `/run/homelab/secrets/nexus-admin/resend_api_key`
- `/run/homelab/secrets/nexus-admin/s3_access_key_id`
- `/run/homelab/secrets/nexus-admin/s3_secret_access_key`
- `/run/homelab/secrets/nexus-admin/supabase_secret_key`

The image expects these values as environment variables and does not include `/bin/sh`, so Compose mounts Docker secrets and uses a Node wrapper to read `/run/secrets/*` before spawning `node server.js`.

Non-secret public configuration stays in `/data/homelab/lab/nexus-admin/env/public.env`. Do not put secret values in that file.

## Deploy

```bash
cd ~/homelab
sudo ./scripts/materialize-secrets.sh nexus-admin
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
