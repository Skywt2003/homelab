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
- `*.dev.skywt` -> `100.64.0.5` for development projects on the `dev` host.
- `nas.skywt` -> `100.64.0.12` for the OMV NAS host.
- `pve.skywt` -> `100.64.0.4` for the Proxmox VE host.
- `gz.skywt` -> `101.33.238.184`.
- `la.skywt` -> `45.32.88.139`.
- `sv.skywt` -> `149.28.207.61` for the Silicon Valley server.

The maintained user rules also publish the internal mail exchanger:

- `skywt.internal MX 10 mail.lab.skywt.`

## Secrets

AdGuard Home's admin password hash is a secret-bearing authentication artifact even though it is not a plain password.

The Git-maintained template must not contain a real admin password hash. When bootstrapping or rotating AdGuard credentials, generate the hash with the AdGuard-supported procedure, store the final hash in Infisical as an externally-generated secret, and materialize it only into the runtime config under `/data/homelab/lab/adguard/conf`.
