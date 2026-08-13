# DNS

This stack runs mosdns as the Tailnet DNS resolver and retains AdGuard Home as
an alternate resolver and the Web UI at `dns.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/adguard/conf`
- `/data/homelab/lab/adguard/work`
- `/data/homelab/lab/mosdns/cache`
- `/data/homelab/lab/mosdns/rules`
- `/data/homelab/lab/mosdns/backups`

AdGuard Home writes `AdGuardHome.yaml` at runtime and may set container-owned
permissions on it. Keep the writable config under `/data`.

The Git-maintained template is:

- `services/dns/adguard/conf/AdGuardHome.yaml.template`

Use it to bootstrap a new runtime config, then update the admin password hash
before starting AdGuard Home.

## Listener ownership

- mosdns is the production resolver on `100.64.0.2:53` over UDP and TCP.
- AdGuard DNS remains available on `100.64.0.2:5354` over UDP and TCP for
  comparison and emergency rollback.
- AdGuard's Web UI remains exposed through Caddy at `https://dns.lab.skywt`.
- mosdns metrics remain loopback-only at `http://127.0.0.1:9092/metrics`.

mosdns uses host networking and drops all Linux capabilities except
`NET_BIND_SERVICE`, which is required to bind privileged port 53. AdGuard uses
a Docker port mapping from Tailnet port 5354 to container port 53. Port 5353 is
left to mDNS users such as Home Assistant.

## AdGuard alternate upstreams

The maintained configuration sends queries in parallel to Cloudflare over
DNS-over-TLS and to AdGuard's unfiltered resolver over DNSCrypt.  Both upstream
definitions contain their endpoint IP, so no plaintext bootstrap resolver is
needed.  Plaintext fallback resolvers are intentionally disabled to prevent a
failed encrypted upstream from silently reintroducing poisoned answers.  Query
limiting remains enabled at 20 QPS per individual IPv4 or IPv6 client instead
of aggregating all current `100.64.0.x` clients into the same `/24` rate-limit
bucket.


## Local records

The same local records are maintained in mosdns and the AdGuard template:

- `*.lab.skywt` -> `100.64.0.2` for services on this `lab` host.
- `*.dev.skywt` -> `100.64.0.5` for development projects on the `dev` host.
- `*.mac-mini.skywt` -> `100.64.0.17` for services on the `mac-mini` host.
- `nas.skywt` -> `100.64.0.12` for the OMV NAS host.
- `pve.skywt` -> `100.64.0.4` for the Proxmox VE host.
- `gz.skywt` -> `101.33.238.184`.
- `la.skywt` -> `45.32.88.139`.
- `sv.skywt` -> `149.28.207.61` for the Silicon Valley server.

The maintained user rules also publish the internal mail exchanger:

- `skywt.internal MX 10 mail.lab.skywt.`

## mosdns v5 production policy

mosdns v5.3.4 became the production resolver on 2026-08-13 after the
side-by-side evaluation in `mosdns/EVALUATION-2026-08-11.md`.

The policy in `mosdns/config.yaml` is evaluated in this order:

1. Local host overrides and the internal MX record.
2. Explicit Apple domains using AliDNS and DNSPod over DoH. The branch falls
   back to clean global DNS only on failure.
3. Proxy/GFW domains using Cloudflare and Google over DoH through Mihomo's
   dedicated SOCKS5 listener at `100.64.0.7:10811`. This check precedes the
   general China set so a list overlap fails closed to clean global DNS.
4. Other China domains using the domestic DoH branch with global fallback.
5. Unclassified domains queried against both branches concurrently. A domestic
   A/AAAA answer is accepted only when it contains an address in the APNIC CN
   set; otherwise the clean global answer is selected.

The global branch deliberately fails closed when `proxy` is unavailable: local
overrides and known CN/Apple domains continue to resolve through domestic DoH,
while global-only answers are not replaced by polluted domestic responses.

Generate an atomic rule snapshot before starting the service:

```bash
sudo install -d -o root -g root /data/homelab/lab/mosdns/cache
sudo ./mosdns/update-rules.py --output /data/homelab/lab/mosdns/rules
```

The generated `manifest.json` records source URLs, hashes, timestamps, and rule
counts. Domain sources follow mosdns' upstream rule-generation approach with
`dnsmasq-china-list` and `cn-blocked-domain`; the IPv4/IPv6 CN set uses the
maintained plain-text release from `Loyalsoldier/geoip`.

Run the comparison suite with the current production/alternate ports:

```bash
./mosdns/compare-dns.py \
  --cn-ip /data/homelab/lab/mosdns/rules/cn_ip.list \
  --output /tmp/dns-comparison.json
```

The mosdns API and Prometheus metrics are loopback-only on
`http://127.0.0.1:9092/metrics`. Route counters named `route_apple`,
`route_proxy`, `route_cn`, and `route_unknown` prove which policy branch was
used without retaining a long-lived per-query log.

## Verification and rollback

Quick verification:

```bash
host -t A probe.lab.skywt 100.64.0.2
host -t A api.m.jd.com 100.64.0.2
host -t A chatgpt.com 100.64.0.2
host -T -t A chatgpt.com 100.64.0.2
host -p 5354 -t A example.com 100.64.0.2
```

Before a DNS-port change, back up both `compose.yml` and
`mosdns/config.yaml`. If mosdns cannot bind or answer on port 53, stop it,
restore the two files, recreate AdGuard on port 53, then recreate mosdns on its
previous listener. Do not remove the AdGuard runtime data when rolling back.

## Secrets

AdGuard Home's admin password hash is a secret-bearing authentication artifact even though it is not a plain password.

The Git-maintained template must not contain a real admin password hash. When bootstrapping or rotating AdGuard credentials, generate the hash with the AdGuard-supported procedure, store the final hash in Infisical as an externally-generated secret, and materialize it only into the runtime config under `/data/homelab/lab/adguard/conf`.
