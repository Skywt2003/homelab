# Caddy

This stack runs the shared reverse proxy for the `lab` host.

Routes are managed by Docker labels on other Compose stacks. For example, the DNS stack publishes AdGuard Home at `http://dns.lab.skywt`.

Caddy owns the shared Docker network:

- `lab-proxy`

Caddy runtime state is stored outside this Git repository:

- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`
