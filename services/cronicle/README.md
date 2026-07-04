# Cronicle

This stack runs Cronicle for `cron.lab.skywt`.

Cronicle is a web-managed task scheduler for scheduled and on-demand jobs. The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

## Runtime Data

Mutable Cronicle state lives outside this Git repository:

- `/data/homelab/lab/cronicle/data` - filesystem storage for users, schedules, events, job history, and setup marker.
- `/data/homelab/lab/cronicle/logs` - Cronicle server and job logs.
- `/data/homelab/lab/cronicle/queue` - local queue state.

## Job Execution Scope

Cronicle jobs run inside the isolated `lab-cronicle` container. This deployment intentionally does not mount `/var/run/docker.sock`, so Cronicle jobs do not get host Docker access.

Do not expose `cron.lab.skywt` outside the trusted lab network without additional authentication.

## Secrets

Cronicle requires one Infisical-generated secret:

- `SECRET_KEY` at Infisical path `/cronicle`, materialized to `/run/homelab/secrets/cronicle/secret_key`.

The entrypoint renders `/opt/cronicle/conf/config.json` from `config/config.template.json` on startup and injects the secret key from the Docker secret. The generated config is not committed.

## First Login

On first startup the entrypoint runs Cronicle filesystem storage setup. Upstream Cronicle creates an initial `admin` user with password `admin`; change that password immediately after first login, or create a new administrator account and remove the bootstrap account.

## Prepare Runtime Data

```bash
sudo mkdir -p /data/homelab/lab/cronicle/{data,logs,queue}
```

Before deploying, create/generate `SECRET_KEY` in Infisical under project `homelab`, environment `prod`, path `/cronicle`, then materialize it:

```bash
cd ~/homelab
sudo ./scripts/materialize-secrets.sh cronicle
```

## Deploy

```bash
cd ~/homelab/services/cronicle
sudo docker compose -f compose.yml up -d --build
```

## Verify

```bash
cd ~/homelab/services/cronicle
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-cronicle
```
