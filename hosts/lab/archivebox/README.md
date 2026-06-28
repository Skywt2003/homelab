# ArchiveBox

This stack runs ArchiveBox for `archive.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

ArchiveBox is configured for single-domain replay because this stack only exposes `archive.lab.skywt`, not wildcard snapshot subdomains.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/archivebox/data`

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/archivebox/data
cd ~/homelab/hosts/lab/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```
