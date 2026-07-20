# Open WebUI

This stack runs Open WebUI at `https://ai.lab.skywt` through the shared Caddy
reverse proxy.

Open WebUI is preconfigured to reach the existing Ollama stack directly over
the shared `lab-proxy` Docker network:

- Ollama URL: `http://lab-ollama:11434`
- Public Open WebUI URL: `https://ai.lab.skywt`

Models installed in Ollama are discovered automatically by Open WebUI. The
recommended model for normal chat is `qwen3:4b-instruct`; refresh the browser's
model selector after pulling a new model if it is already open.

Additional OpenAI-compatible providers, including New API, can be configured
after login from **Admin Settings > Connections**. Use
`http://lab-new-api:3000/v1` when connecting to the local New API container so
traffic stays on the Docker network. Store the corresponding New API token in
Open WebUI rather than in Git.

## Outbound proxy

Open WebUI downloads its default embedding model from Hugging Face during the
first startup. The container routes external HTTP(S) traffic through the lab
proxy at `proxy:10810`; local containers and `*.lab.skywt` bypass it through
`NO_PROXY`. The `proxy` hostname is pinned to the current proxy host Tailscale
address `100.64.0.7` in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/open-webui`

The directory contains the SQLite database, user accounts, chats, uploads,
configuration, and the automatically generated Web UI secret key. Treat the
entire directory as sensitive and include it in backups. The bind mount keeps
the generated key stable when the container is recreated;
`WEBUI_SECRET_KEY_FILE` explicitly places it inside the persisted data
directory.

## First login

The first account registered on a fresh installation becomes the administrator.
Open WebUI then disables further signups automatically. If signup is enabled
again later, new accounts default to the `pending` role and require admin
approval.

## Deploy

Start Ollama first, then deploy Open WebUI:

```bash
sudo mkdir -p /data/homelab/lab/open-webui
cd ~/homelab/services/ollama
sudo docker compose -f compose.yml up -d
cd ~/homelab/services/open-webui
docker compose -f compose.yml config
sudo docker compose -f compose.yml up -d
```

Verify the application health endpoint through Caddy:

```bash
curl --cacert /path/to/lab-root-ca.crt https://ai.lab.skywt/health
```
