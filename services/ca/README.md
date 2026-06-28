# CA Guide

This stack serves the certificate installation guide at `https://ca.lab.skywt`.

The public Caddy route uses the shared `lab-caddy` proxy with `tls internal`.
The local static service only listens inside the Docker network on port `8080`.

`/root.crt` is served from Caddy's internal CA runtime state:

- `/data/homelab/lab/caddy/data/caddy/pki/authorities/local/root.crt`

Only the public root certificate is exposed. Do not publish the private key files
from the same runtime directory.

## Deploy

```bash
cd ~/homelab/services/ca
sudo docker compose -f compose.yml up -d
```
