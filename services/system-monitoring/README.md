# System Monitoring

This stack runs the system-monitoring part of the Prometheus stack for the `lab` host.

It intentionally does **not** run Grafana. Grafana is maintained as the independent
`services/grafana` project so it can also be used for non-system-monitoring data.
This stack only provides metrics collection, storage, push metrics, and alert routing.

## Components

- Prometheus: metrics storage and query API, exposed at `https://prometheus.lab.skywt`.
- Node Exporter: host CPU, memory, disk, network, and OS metrics; internal only.
- cAdvisor: Docker container metrics; internal only.
- Pushgateway: optional push endpoint for batch/one-shot jobs; internal only by default.
- Alertmanager: alert grouping and routing, exposed at `https://alertmanager.lab.skywt`.

Prometheus and Alertmanager are exposed through the shared Caddy reverse proxy by
labels in `compose.yml`. Exporters stay on the stack-local `system-monitoring`
network and are scraped only by Prometheus.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/system-monitoring/prometheus`
- `/data/homelab/lab/system-monitoring/alertmanager`

## Grafana integration

The Grafana project provisions a Prometheus datasource named `System Monitoring`
that points to `http://lab-prometheus:9090` over the shared `lab-proxy` Docker
network. This keeps Grafana reusable while letting it read this stack's metrics.

After deployment, import or build dashboards in Grafana at `https://grafana.lab.skywt`.
Good starter dashboards are Node Exporter and Docker/cAdvisor dashboards from the
Grafana dashboard catalog.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/system-monitoring/prometheus
sudo mkdir -p /data/homelab/lab/system-monitoring/alertmanager
cd ~/homelab/services/system-monitoring
sudo docker compose -f compose.yml up -d
```

## Validate and operate

```bash
cd ~/homelab/services/system-monitoring
docker compose -f compose.yml config
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-prometheus
```

Prometheus can reload configuration without restarting the container because
`--web.enable-lifecycle` is enabled:

```bash
sudo docker exec lab-prometheus wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Alert routing

`alertmanager/alertmanager.yml` currently uses a no-op receiver. Add email,
webhook, DingTalk, WeCom, Feishu, or other receivers there when notification
channels are ready.

## Mihomo Proxy Monitoring

This stack also monitors the Mihomo instance running on the `proxy` host.

Components:

- `lab-mihomo-exporter`: Dockerized `WhereAreBugs/mihomo-prometheus-exporter` running on `lab`, with a local patch that adds `mihomo_proxy_group_selected{group,proxy,type}` for proxy group selection dashboards.
- Prometheus scrape job `mihomo-exporter`.
- Recording rules for probe failure ratio and latency jitter.
- Alerts for exporter down, selected proxy unavailable/high latency, and high probe failure ratio.
- Grafana dashboard `Mihomo Proxy Overview` provisioned under the `System Monitoring` folder.

The exporter runs on `lab` and reads Mihomo's External Controller on the `proxy` Tailscale address `http://100.64.0.7:9090`. The controller is protected by Mihomo's `secret`, and metrics are stored in Prometheus on `lab`.

Runtime secret configuration is kept out of Git in `services/system-monitoring/.env`. Use `services/system-monitoring/.env.example` as the template.
