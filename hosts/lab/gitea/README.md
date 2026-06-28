# Gitea

This stack runs Gitea for `git.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

SSH access is published on host port `2222`, so SSH clone URLs should use `git.lab.skywt:2222`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/gitea/data`

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/gitea/data
sudo chown -R 1000:1000 /data/homelab/lab/gitea/data
cd ~/homelab/hosts/lab/gitea
sudo docker compose -f compose.yml up -d
```
