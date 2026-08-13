# mosdns v5 side-by-side evaluation (2026-08-11)

## Production cutover (2026-08-13)

The side-by-side candidate was approved for production and the listener roles
were changed as follows:

- mosdns now owns `100.64.0.2:53` over UDP and TCP.
- AdGuard DNS remains available at `100.64.0.2:5354` over UDP and TCP.
- AdGuard's Web UI remains available at `https://dns.lab.skywt`.
- The global Cloudflare and Google DoH upstreams continue to use Mihomo SOCKS5
  at `100.64.0.7:10811`; no direct-global fallback was added.

Both containers were healthy with zero restarts after cutover. Local override,
Apple, CN, proxy/global, and unknown-domain queries passed on mosdns UDP/53;
ChatGPT passed over TCP/53; AdGuard answered over both UDP and TCP on 5354. A
real query from the `proxy` Tailnet node also passed against mosdns port 53.

The first cutover attempt safely rolled back because the hardened mosdns
container could not bind privileged port 53 after dropping all capabilities.
The final configuration retains `cap_drop: ALL` and adds only
`NET_BIND_SERVICE`; a loopback low-port preflight and the second cutover then
passed. Pre-cutover backups are stored under
`/data/homelab/lab/mosdns/backups` with timestamp `20260813T031355Z`.

Everything below records the historical side-by-side evaluation performed on
2026-08-11, when AdGuard still owned port 53 and mosdns listened on 5353.

## Deployment state

- mosdns: v5.3.4, healthy, final restart count `0`.
- Trial listeners: `100.64.0.2:5353` on UDP and TCP.
- Metrics: loopback-only `127.0.0.1:9092/metrics`.
- AdGuard remains healthy on `100.64.0.2:53`; it was not restarted or
  reconfigured during this deployment.
- Home Assistant's mDNS wildcard listener and mosdns' address-specific
  UDP/5353 listener are both present. mosdns uses `SO_REUSEPORT`.
- Runtime rules: 111,044 CN domains, 164 Apple-China domains plus explicit
  Apple parent domains, 23,988 proxy domains, and 5,814 CN IPv4/IPv6 prefixes.
- Pre-upstream-change backup:
  `/data/homelab/lab/mosdns/backups/config.yaml.bak.20260811T090300Z`.

The first container start exposed a generated-rule directory mode of `0700`
and entered a restart loop. The new container was stopped, the updater was
fixed to emit directory `0755` and files `0644`, and only then restarted.
AdGuard stayed healthy with restart count `0` and an unchanged start time
throughout. The final mosdns instance has no warnings after its last restart.

Docker Hub could not be reached through the Docker daemon's `proxy:10810`
configuration. The local image was therefore built from the official Linux
amd64 v5.3.4 release binary and the already-present Alpine 3.22 base image.

- Official release ZIP SHA-256:
  `3abcc73080789eb1ccca78dab5049b85ac1e9b8f865ab60158a527b77cd72e85`
- Extracted mosdns binary SHA-256:
  `5357fbb83c89f0a7acad275b72c33aa70d4c720cb5590525660132b10cee8af9`
- Runtime version: `v5.3.4-0-gb732318`

## Policy verified

1. Local overrides and the internal MX record are answered locally and bypass
   the cache/upstreams.
2. Apple and known CN domains use AliDNS and DNSPod over DoH. Failure can fall
   back to the clean global branch.
3. Proxy/GFW domains use Cloudflare and Google DoH through Mihomo SOCKS5 at
   `100.64.0.7:10811`.
4. Unknown domains query domestic and global branches concurrently. Domestic
   A/AAAA answers are accepted only if they contain a CN-prefix address.

Direct global TCP/443 and TCP/853 from `lab` timed out or were reset. Direct
AliDNS DoH returned `31.13.95.18` for `chatgpt.com`, while mosdns returned the
clean Cloudflare pair `104.18.32.47` and `172.64.155.209`. This is the concrete
reason that the global branch must not fall back to a domestic resolver.

After the final restart, route metrics recorded all four policy paths with zero
route errors and zero upstream errors:

| Route | Cache misses handled |
|---|---:|
| Apple | 1 |
| CN | 8 |
| Proxy/global | 5 |
| Unknown dual lookup | 6 |

The cache handled 88 test requests with 68 hits. Domestic and global
forwarders both had zero errors after the final configuration was loaded.

## AdGuard versus mosdns cases

The suite contains 17 cases. Each resolver received five UDP queries and one
TCP query per case. All expected UDP/TCP outcomes passed, including NXDOMAIN.

| Case group | Result |
|---|---|
| Local A/MX overrides | 5/5 answers identical |
| Apple | 2/2 answers identical; explicit Apple route was used |
| CN A records | 3/3 changed from non-CN/global addresses to CN addresses |
| Proxy/global | ChatGPT and Google stayed on clean global answers |
| Unknown | Global answers retained; Microsoft legitimately selected a different Akamai edge |
| IPv6 | AdGuard returned no Bilibili AAAA; mosdns returned eight CN IPv6 endpoints |
| NXDOMAIN | Identical negative result over UDP and TCP |

Warm-query latency is effectively unchanged: the median of per-case p50 values
was 11.213 ms for AdGuard and 11.088 ms for mosdns. Therefore the upgrade's
main value is endpoint correctness, not faster cached DNS processing.

Observed first-query latency across the three CN A cases was 90.136 ms median
for AdGuard and 19.326 ms for mosdns. This is an observed run, not a controlled
cold-cache benchmark, because AdGuard and mosdns started with different cache
histories.

### CDN endpoint impact from `lab`

| Service | AdGuard representative RTT | mosdns representative RTT | Outcome |
|---|---:|---:|---|
| Bilibili | 292.4-408.7 ms | 6.8-19.5 ms | Clear improvement, about 15x-60x |
| Taobao | 323.4 ms | 6.6 ms | Clear improvement, about 49x |
| JD (suite) | 33.9 ms | 29.7 ms minimum, 52.6 ms mean on sampled IP | No clear win in the initial suite |
| JD (follow-up) | 263.5 ms | 28.2-30.3 ms | AdGuard changed to a remote edge; mosdns stayed domestic, about 9x faster |

The initial JD result alone was not a speedup. A follow-up query minutes later
made the policy benefit concrete: AdGuard changed from `103.107.90.239` to
`194.107.19.212` (263.5 ms), while mosdns continued returning the
`123.182.186/190.*` domestic set (28.2-30.3 ms). The issue is therefore unstable
global CDN selection rather than steady resolver processing time.

## Real Tailnet client proof

Queries from the `proxy` Tailnet node reached `100.64.0.2:5353` successfully:

- `probe.lab.skywt` -> `100.64.0.2`
- `api.m.jd.com` -> `123.182.186.22/222` and `123.182.190.22/222`
- `chatgpt.com` -> `104.18.32.47` and `172.64.155.209`
- ChatGPT also succeeded over DNS-over-TCP to port 5353.

## Clear benefits

1. CN sites now receive region-appropriate CDN answers instead of whichever
   answer wins a global parallel race.
2. The unknown-domain branch rejects non-CN domestic answers instead of
   accepting a reachable but polluted or regionally wrong IP.
3. Local overrides and the internal MX record retain parity with AdGuard.
4. Proxy/global domains remain clean despite demonstrable domestic pollution.
5. Per-route and per-upstream metrics make policy selection and failures
   observable without retaining AdGuard-sized query logs.
6. Cached-query latency does not materially regress despite the dual-lookup
   policy.

## Constraints assessed before port-53 cutover (historical)

1. The global branch currently depends on `proxy` because the ISP path resets
   direct global DoH/DoT. If `proxy` is down, local and known CN/Apple DNS keep
   working, but global-only domains fail closed. This is safer than pollution,
   but weaker than the current AdGuard DNSCrypt fallback for availability.
2. Unknown domains are sent to both domestic and global providers on cache
   miss, increasing query volume and disclosure to two resolver groups.
3. The test listener is plain DNS on 5353. Native client-facing DoH/DoT should
   be enabled with the internal CA certificate only as a separate, validated
   cutover step.
4. Applications using their own HTTPDNS, including some Bilibili paths, can
   bypass the system resolver and are outside mosdns' control.

Historical recommendation: keep the side-by-side deployment running until the
proxy-dependency risk was accepted or a proxy-independent clean fallback was
added. On 2026-08-13 the proxy-dependency risk was explicitly accepted because
Mihomo has multiple fallbacks and clients can disable Tailscale to return to
their local network DNS. The cutover therefore retained the fail-closed global
branch without adding a direct-global fallback.

Raw evidence is retained locally in:

- `logs/mosdns-v5-comparison-20260811.json`
- `logs/mosdns-v5-cdn-rtt-20260811.tsv`
