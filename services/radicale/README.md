# Radicale

This stack runs the migrated Radicale CalDAV/CardDAV service for `vcards.lab.skywt`.

The service is exposed through the shared Caddy reverse proxy by labels in `compose.yml`. It does not publish port 5232 directly.

The image is pinned to the exact digest and Radicale 3.3.2 image used by the former `gz.skywt` deployment.

## Configuration and runtime data

- Git-maintained configuration: `services/radicale/config`
- Mutable collections: `/data/homelab/lab/radicale/data`

The migrated configuration is unchanged except that `htpasswd_filename` points to the Compose secret at `/run/secrets/users` instead of the former `/config/users` path.

## Secrets

The legacy `users` authentication file is an externally generated secret imported from the former `gz.skywt` deployment. Infisical stores it as:

- Project: `homelab`
- Environment: `prod`
- Path: `/radicale`
- Name: `USERS`

It is materialized to `/run/homelab/secrets/radicale/users` and mounted into the container as `/run/secrets/users`. The host directory remains root-only (`0700`); the file is `0444` because Compose ignores ownership overrides for file-backed secrets and Radicale runs as UID 2999 inside the container. Do not commit the file or print its contents.

## Deploy

```bash
sudo install -d -m 0755 -o 2999 -g 2999 /data/homelab/lab/radicale/data
cd ~/homelab
sudo ./scripts/materialize-secrets.sh radicale
cd ~/homelab/services/radicale
sudo docker compose -f compose.yml up -d
```
