# ArchiveBox

This stack runs ArchiveBox for `archive.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

ArchiveBox is configured for single-domain replay because this stack only exposes `archive.lab.skywt`, not wildcard snapshot subdomains.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/archivebox/data`

## Secrets

This stack currently has no Compose-mounted secrets.

ArchiveBox users, passwords, and application-generated credentials live in the runtime data directory and must not be copied into Git. If future bootstrap credentials are needed, store them in Infisical and mount them according to `docs/secret-management-sop.md`.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/archivebox/data
cd ~/homelab/services/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```
