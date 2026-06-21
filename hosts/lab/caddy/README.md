# Caddy

The running Caddy container is currently defined in `../dns/compose.yml`.

Routes are managed by Docker labels, including the AdGuard Home route for `http://dns.lab.skynet`.

Caddy runtime state is stored outside this Git repository:

- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`
