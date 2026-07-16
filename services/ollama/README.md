# Ollama

This stack runs the Ollama API at `https://llm.lab.skywt` through the shared
Caddy reverse proxy.

Model data is stored outside this repository at:

- `/data/homelab/lab/ollama`

Deploy the service and pull the default model:

```bash
sudo mkdir -p /data/homelab/lab/ollama
sudo docker compose -f compose.yml up -d
sudo docker exec lab-ollama ollama pull qwen3:4b
```

Check the API:

```bash
curl --cacert /path/to/lab-root-ca.crt https://llm.lab.skywt/api/tags
```

The Ollama API does not provide authentication. This endpoint is intended only
for clients that can reach the private lab network and trust the lab CA.
