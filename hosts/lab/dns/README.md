# DNS

This stack runs AdGuard Home for `dns.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/adguard/work`
