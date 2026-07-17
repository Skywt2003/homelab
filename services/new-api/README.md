# New API

This stack runs New API, a self-hosted LLM API gateway and AI asset management system, for `ai-api.lab.skywt`.

New API is exposed through the shared Caddy reverse proxy by labels in `compose.yml`:

- URL: `https://ai-api.lab.skywt`
- Upstream port: `3000`
- TLS: Caddy internal CA

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/new-api/data`

## Provider outbound proxy

The container is configured to route outbound API/provider traffic through the lab proxy at `proxy:10810`:

- `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and lowercase variants are set to `http://proxy:10810`.
- `RELAY_PROXY` is set to `http://proxy:10810` for New API / One API compatible model relay requests.
- `USER_CONTENT_REQUEST_PROXY` is set to `http://proxy:10810` for user-upload content fetches.
- `proxy` is pinned with `extra_hosts` to the current proxy host Tailscale address `100.64.0.7`.

## Secrets

Provider API keys, model relay credentials, admin credentials, and user tokens are secrets.

New API stores operational secrets in its runtime database under `/data/homelab/lab/new-api/data`; do not copy that data into Git. Credentials supplied through Compose belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md).

Default or first-run admin passwords are externally-generated or service-generated secrets until changed and recorded in the appropriate password manager/Infisical workflow.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/new-api/data
cd ~/homelab/services/new-api
docker compose -f compose.yml config
sudo docker compose -f compose.yml up -d
```

After first start, visit `https://ai-api.lab.skywt` and change the default admin password immediately if New API initializes one.
