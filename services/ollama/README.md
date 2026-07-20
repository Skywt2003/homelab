# Ollama

This stack runs the Ollama API at `https://llm.lab.skywt` through the shared
Caddy reverse proxy.

Model data is stored outside this repository at:

- `/data/homelab/lab/ollama`

The container is intentionally limited to 3 CPUs and 5.5 GiB of memory so a
model request cannot consume every vCPU assigned to the shared `lab` VM. Only
one model and one parallel request are allowed, the context is capped at 4096
tokens, and idle models are unloaded after two minutes.

External model downloads use the lab HTTP proxy at `proxy:10810`. Local
containers and `*.lab.skywt` bypass it through `NO_PROXY`; the proxy hostname
is pinned to `100.64.0.7` in `compose.yml`.

Deploy the service and pull the default model:

```bash
sudo mkdir -p /data/homelab/lab/ollama
sudo docker compose -f compose.yml up -d
sudo docker exec lab-ollama ollama pull qwen3:4b-instruct
```

`qwen3:4b-instruct` is the recommended model for normal chat. The shorter
`qwen3:4b` tag currently refers to the thinking variant and is better reserved
for prompts where extended reasoning is useful.

Check the API:

```bash
curl --cacert /path/to/lab-root-ca.crt https://llm.lab.skywt/api/tags
```

The Ollama API does not provide authentication. This endpoint is intended only
for clients that can reach the private lab network and trust the lab CA.
