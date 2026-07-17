# ArchiveBox

This stack runs ArchiveBox for `archive.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

ArchiveBox uses single-domain replay through `archive.lab.skywt`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/archivebox/data`

## Secrets

ArchiveBox users, passwords, and application-generated credentials live in the runtime data directory and must not be copied into Git. Provisioned bootstrap credentials belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md).

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/archivebox/data
cd ~/homelab/services/archivebox
sudo docker compose -f compose.yml run --rm archivebox init
sudo docker compose -f compose.yml up -d
```
