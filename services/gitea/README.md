# Gitea

This stack runs Gitea for `git.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

SSH access is published on host port `2222`, so SSH clone URLs should use `git.lab.skywt:2222`.

## Outbound proxy

GitHub migrations and repository mirror updates use the lab HTTP proxy at
`proxy:10810`. Gitea's `[proxy]` support is enabled for GitHub API, repository,
and asset hosts, while standard uppercase and lowercase proxy variables are
also supplied to Git and Git LFS subprocesses. Local containers and
`*.lab.skywt` bypass the proxy through `NO_PROXY`.

The `proxy` hostname is pinned in `compose.yml` to the proxy host's current
Tailscale address, `100.64.0.7`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/gitea/data`

## Secrets

Gitea application secrets, users, SSH keys, tokens, and repository data live under `/data/homelab/lab/gitea/data` and must not be copied into Git. Provisioned bootstrap secrets belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md).

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/gitea/data
sudo chown -R 1000:1000 /data/homelab/lab/gitea/data
cd ~/homelab/services/gitea
docker compose -f compose.yml config
sudo docker compose -f compose.yml up -d
```

After recreating the container, verify that GitHub is reachable from the same
runtime environment used by Gitea:

```bash
sudo docker exec lab-gitea git ls-remote https://github.com/go-gitea/gitea.git HEAD
```
