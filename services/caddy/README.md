# Caddy

This stack runs the shared reverse proxy for the `lab` host.

Routes are managed by Docker labels on other Compose stacks. For example, the DNS stack publishes AdGuard Home at `https://dns.lab.skywt`.

Home Assistant is the exception: it uses host networking for local device discovery, so `home.lab.skywt` is defined in `acme-server.Caddyfile` and proxies to `host.docker.internal:8123`. The Compose `host-gateway` entry makes that name resolve to the `lab` host from inside Caddy.

The same Caddy instance also exposes the internal ACME server at `https://acme.lab.skywt` for selected internal names. It currently allows `*.lab.skywt`, `*.dev.skywt`, `nas.skywt`, and `pve.skywt`. The NAS host runs its own Caddy and obtains the `nas.skywt` certificate from this ACME server; the PVE host uses its built-in ACME client for `pve.skywt`.

The ACME server issues certificates with a 72-hour lifetime. This accommodates
PVE's daily renewal job while retaining short-lived internal certificates.

Caddy owns the shared Docker network:

- `lab-proxy`

Caddy runtime state is stored outside this Git repository:

- `/data/homelab/lab/caddy/data`
- `/data/homelab/lab/caddy/config`

## Secrets

Caddy's internal CA private keys and ACME/runtime state under `/data/homelab/lab/caddy/data` are secrets. The public root certificate is not a secret.
