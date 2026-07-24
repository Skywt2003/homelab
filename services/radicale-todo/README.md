# Radicale Calendar and Reminders

This is an independent Radicale CalDAV deployment for Apple Calendar and Apple Reminders at `todo.lab.skywt`. It is separate from the existing `vcards.lab.skywt` Radicale instance and uses a different container, configuration, secret, and runtime-data path.

## Collections

The account owns two direct child collections so Apple clients can discover each data type independently:

- `https://todo.lab.skywt/skywt/calendar/` - `VEVENT` calendar
- `https://todo.lab.skywt/skywt/tasks/` - `VTODO` reminder list

Use `https://todo.lab.skywt` as the CalDAV server URL. Caddy terminates HTTPS with the lab internal CA and proxies to port `5232`; no container port is published directly.

## Runtime Data

Mutable collections live at `/data/homelab/lab/radicale-todo/data` on `lab`.

Prepare the directory before first deployment:

```bash
sudo install -d -m 0755 -o 2999 -g 2999 /data/homelab/lab/radicale-todo/data
```

## Secrets

Infisical stores the account material under project `homelab`, environment `prod`, path `/radicale-todo`:

- `ACCOUNT_PASSWORD` - Infisical-generated password used when configuring Apple clients
- `USERS` - externally generated SHA-512 `htpasswd` entry derived from the account password

Only `USERS` is materialized to `/run/homelab/secrets/radicale-todo/users` and mounted at `/run/secrets/users`. The host secret directory is root-only (`0700`); the mounted file is `0444` because Compose file-backed secrets ignore ownership overrides and Radicale runs as UID 2999.

## Deploy

```bash
sudo install -d -m 0755 -o 2999 -g 2999 /data/homelab/lab/radicale-todo/data
cd ~/homelab
sudo ./scripts/materialize-secrets.sh radicale-todo
cd ~/homelab/services/radicale-todo
sudo docker compose -f compose.yml up -d
```

## Validate

```bash
cd ~/homelab/services/radicale-todo
docker compose -f compose.yml config
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-radicale-todo
curl -k -u 'skywt:<password>' -X PROPFIND -H 'Depth: 1' \
  https://todo.lab.skywt/skywt/
```
