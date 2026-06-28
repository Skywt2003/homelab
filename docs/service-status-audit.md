# Service Status Audit

Audit date: 2026-06-28 UTC

Command used:

```bash
sudo docker ps -a --filter 'name=lab-'
sudo docker inspect <lab containers>
```

## Summary

All containers declared by the Compose files under `services/` exist on this host and were running at audit time. No extra `lab-*` containers were found outside the repository-managed stacks.

Health status is only available for containers that define a healthcheck; `no-healthcheck` means Docker has no healthcheck configured, not that the service is unhealthy.

## Container status

| Stack | Container | Compose service | State | Health |
| --- | --- | --- | --- | --- |
| `dns` | `lab-adguard` | `adguard` | running | no-healthcheck |
| `caddy` | `lab-caddy` | `caddy` | running | no-healthcheck |
| `ca` | `lab-ca` | `ca` | running | no-healthcheck |
| `dashy` | `lab-dashy` | `dashy` | running | healthy |
| `archivebox` | `lab-archivebox` | `archivebox` | running | no-healthcheck |
| `gitea` | `lab-gitea` | `gitea` | running | no-healthcheck |
| `grafana` | `lab-grafana` | `grafana` | running | no-healthcheck |
| `rsshub` | `lab-rsshub` | `rsshub` | running | healthy |
| `rsshub` | `lab-rsshub-browserless` | `browserless` | running | healthy |
| `rsshub` | `lab-rsshub-redis` | `redis` | running | healthy |
| `docker-registry` | `lab-docker-registry` | `docker-registry` | running | healthy |
| `system-monitoring` | `lab-prometheus` | `prometheus` | running | no-healthcheck |
| `system-monitoring` | `lab-node-exporter` | `node-exporter` | running | no-healthcheck |
| `system-monitoring` | `lab-cadvisor` | `cadvisor` | running | healthy |
| `system-monitoring` | `lab-pushgateway` | `pushgateway` | running | no-healthcheck |
| `system-monitoring` | `lab-mihomo-exporter` | `mihomo-exporter` | running | no-healthcheck |
| `system-monitoring` | `lab-alertmanager` | `alertmanager` | running | no-healthcheck |

## Runtime configuration note

AdGuard is intentionally configured with these wildcard rewrites:

```yaml
- domain: '*.lab.skywt'
  answer: 100.64.0.2
  enabled: true
- domain: '*.dev.skywt'
  answer: 100.64.0.5
  enabled: true
```

The `*.dev.skywt` rewrite is kept so lab DNS can resolve development projects on the separate `dev` host. The projects themselves are not managed by this repository.

The mounted Caddy ACME server file only allows `*.lab.skywt`; this repository does not manage TLS routing for `*.dev.skywt`.

## Items to confirm

- No runtime mismatch was found between repository Compose definitions and current `lab-*` containers.
- Several important services do not define Docker healthchecks: AdGuard Home, Caddy, CA guide, ArchiveBox, Gitea, Grafana, Prometheus, Node Exporter, Pushgateway, Mihomo exporter, and Alertmanager. This is expected from the current Compose files, but adding healthchecks would make future status audits stricter.

## HTTPS route smoke test

Routes were also checked locally through Caddy with `curl --resolve <domain>:443:127.0.0.1 -k` to avoid depending on client DNS or local CA trust during the audit.

| URL | HTTP status |
| --- | --- |
| `https://index.lab.skywt` | 200 |
| `https://dns.lab.skywt` | 302 |
| `https://grafana.lab.skywt` | 302 |
| `https://prometheus.lab.skywt` | 302 |
| `https://alertmanager.lab.skywt` | 200 |
| `https://archive.lab.skywt` | 302 |
| `https://git.lab.skywt` | 200 |
| `https://rsshub.lab.skywt` | 200 |
| `https://ca.lab.skywt` | 200 |
| `https://docker.lab.skywt/v2/` | 200 |

Redirect statuses are expected for services that send unauthenticated users to a login or setup route.
