# Grafana

This stack runs Grafana for `grafana.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/grafana/data`

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/grafana/data
sudo chown -R 472:472 /data/homelab/lab/grafana/data
cd ~/homelab/hosts/lab/grafana
sudo docker compose -f compose.yml up -d
```
