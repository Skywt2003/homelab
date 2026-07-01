# Caddy

This stack runs the shared reverse proxy for the `lab` host.

Routes are managed by Docker labels on other Compose stacks. For example, the DNS stack publishes AdGuard Home at `https://dns.lab.skywt`.

Caddy owns the shared Docker network:

- `lab-proxy`

Caddy runtime state is stored outside this Git repository:

- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`

## Secrets

Caddy's internal CA private keys and ACME/runtime state under `/data/homelab/lab/caddy/data` are secrets. The public root certificate is not a secret.

This stack currently has no Compose-mounted secrets. If future Caddy credentials are required, classify them under `docs/secret-management-sop.md` and mount them from `/run/homelab/secrets/caddy` through Docker Compose secrets.
