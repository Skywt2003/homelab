# Homelab

Centralized configuration for lab infrastructure.

## Layout

- `hosts/lab/dns`: DNS stack for `dns.lab.skywt`.
- `hosts/lab/caddy`: Caddy notes for routes owned by the lab host.
- `hosts/dev`: placeholder for other hosts.
- `shared`: shared scripts, templates, and common configuration.

## Runtime Data

Runtime state that is not manually maintained in Git lives under `/data/homelab/lab` on the `lab` host.

Current paths:

- `/data/homelab/lab/adguard/work`
- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`

## Deploy DNS

```bash
cd ~/homelab/hosts/lab/dns
sudo docker compose -f compose.yml up -d
```
