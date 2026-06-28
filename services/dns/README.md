# DNS

This stack runs AdGuard Home for `dns.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/adguard/conf`
- `/data/homelab/lab/adguard/work`

AdGuard Home writes `AdGuardHome.yaml` at runtime and may set container-owned
permissions on it. Keep the writable config under `/data`.

The Git-maintained template is:

- `services/dns/adguard/conf/AdGuardHome.yaml.template`

Use it to bootstrap a new runtime config, then update the admin password hash
before starting AdGuard Home.


## Local rewrites

The maintained AdGuard template includes these local wildcard rewrites:

- `*.lab.skywt` -> `100.64.0.2` for services on this `lab` host.
- `*.dev.skywt` -> `100.64.0.5` for development projects on the separate `dev` host. The projects themselves are not managed by this repository.
