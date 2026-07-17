# Caddy

This stack runs the shared reverse proxy for the `lab` host.

Routes are managed by Docker labels on other Compose stacks. For example, the DNS stack publishes AdGuard Home at `https://dns.lab.skywt`.

The same Caddy instance also exposes the internal ACME server at `https://acme.lab.skywt` for selected internal names. It currently allows `*.lab.skywt`, `*.dev.skywt`, and `nas.skywt`; the NAS host runs its own Caddy and obtains the `nas.skywt` certificate from this ACME server.

Caddy owns the shared Docker network:

- `lab-proxy`

Caddy runtime state is stored outside this Git repository:

- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`

## Secrets

Caddy's internal CA private keys and ACME/runtime state under `/data/homelab/lab/caddy/data` are secrets. The public root certificate is not a secret.
