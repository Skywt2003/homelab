# Homelab

Centralized configuration for lab infrastructure.

## Layout

- `hosts/lab/dns`: DNS stack for `dns.lab.skynet`.
- `hosts/lab/caddy`: Caddy runtime directories used by the DNS stack.
- `hosts/dev`: placeholder for other hosts.
- `shared`: shared scripts, templates, and common configuration.

## Deploy DNS

```bash
cd ~/homelab/hosts/lab/dns
sudo docker compose up -d
```
