# Grafana

This stack runs Grafana for `grafana.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Provisioned datasources are maintained under `provisioning/datasources/`. The
`System Monitoring` Prometheus datasource points to the
`services/system-monitoring` stack over the shared Docker network.
Provisioned dashboards are maintained under `dashboards/` and loaded by
`provisioning/dashboards/`. Host dashboards include `Lab Host Overview` and
`PVE Host and VM Overview`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/grafana/data`

## Secrets

Grafana users, sessions, API keys, and datasource credentials live in Grafana runtime data unless explicitly provisioned. Provisioned credentials belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md); keep them out of provisioning files.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/grafana/data
sudo chown -R 472:472 /data/homelab/lab/grafana/data
cd ~/homelab/services/grafana
sudo docker compose -f compose.yml up -d
```
