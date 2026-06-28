# Homelab

Centralized configuration for lab infrastructure.

## Layout

- `docs`: operating procedures and maintenance notes.
- `hosts/lab/dns`: DNS stack for `dns.lab.skywt`.
- `hosts/lab/caddy`: Caddy notes for routes owned by the lab host.
- `hosts/lab/ca`: certificate installation guide for `ca.lab.skywt`.
- `hosts/lab/archivebox`: ArchiveBox stack for `archive.lab.skywt`.
- `hosts/lab/dashy`: Dashy service index for `index.lab.skywt`.
- `hosts/lab/gitea`: Gitea stack for `git.lab.skywt`.
- `hosts/lab/grafana`: Grafana stack for `grafana.lab.skywt`.
- `hosts/lab/system-monitoring`: Prometheus-based host, container, and Mihomo proxy monitoring stack.
- `hosts/lab/rsshub`: RSSHub stack for `rsshub.lab.skywt`.
- `hosts/lab/docker-registry`: Docker Registry stack for `docker.lab.skywt`.
- `hosts/dev`: placeholder for other hosts.
- `shared`: shared scripts, templates, and common configuration.

## SOPs

- [New Service SOP](docs/new-service-sop.md)
- [Dev Project Exposure SOP](docs/dev-project-exposure-sop.md)

## Runtime Data

Runtime state that is not manually maintained in Git lives under `/data/homelab/lab` on the `lab` host.

Current paths:

- `/data/homelab/lab/adguard/conf`
- `/data/homelab/lab/adguard/work`
- `/data/homelab/lab/archivebox/data`
- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`
- `/data/homelab/lab/gitea/data`
- `/data/homelab/lab/grafana/data`
- `/data/homelab/lab/system-monitoring/prometheus`
- `/data/homelab/lab/system-monitoring/alertmanager`
- `/data/homelab/lab/rsshub/redis`
- `/data/homelab/lab/docker-registry/data`

## Deploy DNS

```bash
cd ~/homelab/hosts/lab/dns
sudo docker compose -f compose.yml up -d
```

## Deploy CA Guide

```bash
cd ~/homelab/hosts/lab/ca
sudo docker compose -f compose.yml up -d
```

## Deploy Dashy

```bash
cd ~/homelab/hosts/lab/dashy
sudo docker compose -f compose.yml up -d
```

## Deploy ArchiveBox

```bash
sudo mkdir -p /data/homelab/lab/archivebox/data
cd ~/homelab/hosts/lab/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```

## Deploy Gitea

```bash
sudo mkdir -p /data/homelab/lab/gitea/data
sudo chown -R 1000:1000 /data/homelab/lab/gitea/data
cd ~/homelab/hosts/lab/gitea
sudo docker compose -f compose.yml up -d
```

## Deploy Grafana

```bash
sudo mkdir -p /data/homelab/lab/grafana/data
sudo chown -R 472:472 /data/homelab/lab/grafana/data
cd ~/homelab/hosts/lab/grafana
sudo docker compose -f compose.yml up -d
```

## Deploy System Monitoring

Mihomo proxy monitoring is integrated into this stack. Configure `hosts/lab/system-monitoring/.env` from `.env.example` before deployment when enabling the exporter.


```bash
sudo mkdir -p /data/homelab/lab/system-monitoring/prometheus
sudo mkdir -p /data/homelab/lab/system-monitoring/alertmanager
cd ~/homelab/hosts/lab/system-monitoring
sudo docker compose -f compose.yml up -d
```

## Deploy RSSHub

```bash
sudo mkdir -p /data/homelab/lab/rsshub/redis
cd ~/homelab/hosts/lab/rsshub
sudo docker compose -f compose.yml up -d
```

## Deploy Docker Registry

```bash
sudo mkdir -p /data/homelab/lab/docker-registry/data
cd ~/homelab/hosts/lab/docker-registry
sudo docker compose -f compose.yml up -d
```
