# Homelab

Configuration for services running on the `lab` host only.

This repository intentionally no longer manages `dev` host projects. Development projects on `dev` are expected to be run and exposed independently from this Docker-based lab service layout.

## Layout

- `services/apprise-api`: Apprise API notification gateway for `notify.lab.skywt`.
- `services/archivebox`: ArchiveBox for `archive.lab.skywt`.
- `services/ca`: certificate installation guide for `ca.lab.skywt`.
- `services/caddy`: shared Caddy reverse proxy and internal ACME endpoint for lab services.
- `services/dashy`: Dashy service index for `index.lab.skywt`.
- `services/dns`: AdGuard Home DNS stack for `dns.lab.skywt`.
- `services/docker-registry`: Docker Registry for `docker.lab.skywt`.
- `services/gitea`: Gitea for `git.lab.skywt`.
- `services/grafana`: Grafana for `grafana.lab.skywt`.
- `services/new-api`: New API LLM gateway for `ai-api.lab.skywt`.
- `services/nexus-admin`: Nexus Admin for `blog-admin.lab.skywt`.
- `services/rsshub`: RSSHub for `rsshub.lab.skywt`.
- `services/system-monitoring`: Prometheus, exporters, Alertmanager, and Mihomo proxy monitoring.
- `docs`: operating procedures and audit notes.

## SOPs

- [New Service SOP](docs/new-service-sop.md)
- [Service Status Audit](docs/service-status-audit.md)

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
- `/data/homelab/lab/docker-registry/data`
- `/data/homelab/lab/gitea/data`
- `/data/homelab/lab/grafana/data`
- `/data/homelab/lab/new-api/data`
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
sudo mkdir -p /data/homelab/lab/docker-registry/data
sudo mkdir -p /data/homelab/lab/gitea/data
sudo chown -R 1000:1000 /data/homelab/lab/gitea/data
sudo mkdir -p /data/homelab/lab/grafana/data
sudo chown -R 472:472 /data/homelab/lab/grafana/data
sudo mkdir -p /data/homelab/lab/new-api/data
sudo mkdir -p /data/homelab/lab/rsshub/redis
sudo mkdir -p /data/homelab/lab/system-monitoring/prometheus
sudo mkdir -p /data/homelab/lab/system-monitoring/alertmanager
```

ArchiveBox still requires initialization before the first normal start:

```bash
cd ~/homelab/services/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```

System monitoring reads the Mihomo exporter token from `services/system-monitoring/.env`; create it from `.env.example` before deploying that stack.
