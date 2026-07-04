# Homelab

Configuration for services running on the `lab` host only.

This repository intentionally no longer manages `dev` host projects. Development projects on `dev` are expected to be run and exposed independently from this Docker-based lab service layout.

## Layout

- `services/apprise-api`: Apprise API notification gateway for `notify.lab.skywt`.
- `services/archivebox`: ArchiveBox for `archive.lab.skywt`.
- `services/ca`: certificate installation guide for `ca.lab.skywt`.
- `services/calibre-web`: Calibre-Web ebook library for `books.lab.skywt`.
- `services/caddy`: shared Caddy reverse proxy and internal ACME endpoint for lab services.
- `services/cronicle`: Cronicle web-managed task scheduler for `cron.lab.skywt`.
- `services/dashy`: Dashy service index for `index.lab.skywt`.
- `services/dns`: AdGuard Home DNS stack for `dns.lab.skywt`.
- `services/docker-registry`: Docker Registry for `docker.lab.skywt`.
- `services/gitea`: Gitea for `git.lab.skywt`.
- `services/grafana`: Grafana for `grafana.lab.skywt`.
- `services/infisical`: Infisical secret management platform for `secrets.lab.skywt`.
- `services/new-api`: New API LLM gateway for `ai-api.lab.skywt`.
- `services/nexus-admin`: Nexus Admin for `blog-admin.lab.skywt`.
- `services/rsshub`: RSSHub for `rsshub.lab.skywt`.
- `services/system-monitoring`: Prometheus, exporters, Alertmanager, and Mihomo proxy monitoring.
- `docs`: operating procedures and audit notes.

## SOPs

- [New Service SOP](docs/new-service-sop.md)
- [Secret Management SOP](docs/secret-management-sop.md)
- [Service Status Audit](docs/service-status-audit.md)
- [Secret Governance Audit - 2026-06-30](docs/secret-governance-audit-2026-06-30.md)

## Secret Management

Real secrets must not be committed to this repository. Infisical at `https://secrets.lab.skywt` is the authoritative inventory for lab service secrets. New services must follow [Secret Management SOP](docs/secret-management-sop.md).

Standard flow for service secrets:

1. Classify each secret as either Infisical-generated or externally-generated.
2. Store the final value in Infisical under project `homelab`, environment `prod`, path `/<service>`.
3. Materialize deploy-time files under `/run/homelab/secrets/<service>/` on the `lab` host.
4. Mount those files into containers through Docker Compose `secrets` and prefer `/run/secrets/<name>` plus `_FILE` variables.

Secret origin classes:

- **Infisical-generated**: opaque random values such as database passwords, session/JWT/cookie secrets, registry HTTP secrets, or internal webhook tokens. Generate these directly in Infisical.
- **Externally-generated**: values that must come from another system or tool, such as third-party API keys, OAuth client secrets, TLS/SSH/WireGuard private keys, `htpasswd`/bcrypt hashes, provider-issued tokens, and service-generated first-run credentials. Generate or obtain them externally, then store the final value in Infisical.

Exception: Infisical's own bootstrap secrets live outside Git in `/data/homelab/lab/infisical/env/infisical.env` because Infisical cannot depend on itself to start. Back up that file securely together with Infisical PostgreSQL data.

Service secrets are materialized with `scripts/materialize-secrets.sh`. Do not copy legacy repo-local `.env` patterns into new services.

## Runtime Data

Mutable runtime state is not maintained in Git. It lives under `/data/homelab/lab` on the `lab` host.

Current paths:

- `/data/homelab/lab/adguard/conf`
- `/data/homelab/lab/adguard/work`
- `/data/homelab/lab/apprise-api/config`
- `/data/homelab/lab/apprise-api/attach`
- `/data/homelab/lab/apprise-api/plugin`
- `/data/homelab/lab/archivebox/data`
- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`
- `/data/homelab/lab/calibre-web/config`
- `/data/homelab/lab/calibre-web/books`
- `/data/homelab/lab/cronicle/data`
- `/data/homelab/lab/cronicle/logs`
- `/data/homelab/lab/cronicle/queue`
- `/data/homelab/lab/docker-registry/data`
- `/data/homelab/lab/gitea/data`
- `/data/homelab/lab/grafana/data`
- `/data/homelab/lab/infisical/env`
- `/data/homelab/lab/infisical/postgres`
- `/data/homelab/lab/infisical/redis`
- `/data/homelab/lab/new-api/data`
- `/data/homelab/lab/nexus-admin/env`
- `/data/homelab/lab/rsshub/env`
- `/data/homelab/lab/rsshub/redis`
- `/data/homelab/lab/system-monitoring/prometheus`
- `/data/homelab/lab/system-monitoring/alertmanager`

## Deploy

Each stack is deployed from its directory:

```bash
cd ~/homelab/services/<service>
sudo docker compose -f compose.yml up -d
```

Services with first-run data directories may need preparation:

```bash
sudo mkdir -p /data/homelab/lab/apprise-api/{config,attach,plugin}
sudo chown -R 1000:1000 /data/homelab/lab/apprise-api
sudo mkdir -p /data/homelab/lab/archivebox/data
sudo mkdir -p /data/homelab/lab/calibre-web/{config,books}
sudo chown -R 1000:1000 /data/homelab/lab/calibre-web
sudo mkdir -p /data/homelab/lab/cronicle/{data,logs,queue}
sudo mkdir -p /data/homelab/lab/docker-registry/data
sudo mkdir -p /data/homelab/lab/gitea/data
sudo chown -R 1000:1000 /data/homelab/lab/gitea/data
sudo mkdir -p /data/homelab/lab/grafana/data
sudo chown -R 472:472 /data/homelab/lab/grafana/data
sudo mkdir -p /data/homelab/lab/infisical/{env,postgres,redis}
sudo mkdir -p /data/homelab/lab/new-api/data
sudo mkdir -p /data/homelab/lab/nexus-admin/env
sudo mkdir -p /data/homelab/lab/rsshub/{env,redis}
sudo mkdir -p /data/homelab/lab/system-monitoring/prometheus
sudo mkdir -p /data/homelab/lab/system-monitoring/alertmanager
```

ArchiveBox still requires initialization before the first normal start:

```bash
cd ~/homelab/services/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```

Before deploying services that use secrets, materialize current values from Infisical on the lab host:

```bash
# Requires /data/homelab/lab/infisical/client.env with INFISICAL_PROJECT_ID and either INFISICAL_CLIENT_ID/INFISICAL_CLIENT_SECRET or INFISICAL_TOKEN.
sudo ./scripts/materialize-secrets.sh all
```

`sudo ./scripts/import-legacy-secrets.sh` was used for the one-time migration from root-only legacy files into Infisical. Do not recreate legacy secret files for normal operation.
