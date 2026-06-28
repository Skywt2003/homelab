# DNS

This stack runs AdGuard Home for `dns.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/adguard/conf`
- `/data/homelab/lab/adguard/work`

AdGuard Home writes `AdGuardHome.yaml` at runtime and may set container-owned
permissions on it. Keep the writable config under `/data`.

The Git-maintained template is:

- `hosts/lab/dns/adguard/conf/AdGuardHome.yaml.template`

Use it to bootstrap a new runtime config, then update the admin password hash
before starting AdGuard Home.
