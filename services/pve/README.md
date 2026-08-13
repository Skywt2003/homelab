# Proxmox VE Web UI

The PVE host exposes its native `pveproxy` Web UI at `https://pve.skywt`.

- mosdns resolves `pve.skywt` to the PVE Tailscale address `100.64.0.4`.
- PVE's built-in ACME client obtains the certificate from
  `https://acme.lab.skywt/acme/local/directory` using the account
  `lab-caddy` and the HTTP-01 challenge.
- `pveproxy` remains on its standard port `8006`.
- A host-local nftables NAT table redirects TCP port 443 on the Tailscale
  address to port 8006 without terminating TLS or hiding the client address.

The lab Caddy root certificate is installed on PVE as:

```text
/usr/local/share/ca-certificates/lab-caddy-root.crt
```

PVE stores the ACME account and issued certificate under `/etc/pve`. The ACME
account private key and certificate private key are secrets and must not be
committed to this repository.

## Host files

Install the maintained files on PVE as follows:

```text
pve-webui-443.nft     -> /etc/pve-webui-443.nft
pve-webui-443.service -> /etc/systemd/system/pve-webui-443.service
```

Then enable the mapping:

```bash
systemctl daemon-reload
systemctl enable --now pve-webui-443.service
```

The generic `nftables.service` remains disabled because its stock
`/etc/nftables.conf` flushes the complete ruleset and can conflict with the
Proxmox firewall. The dedicated unit owns only the `inet pve_webui_443` table
and starts after both Proxmox firewall services.

## Verification

```bash
getent ahostsv4 pve.skywt
curl --noproxy '*' https://pve.skywt/
nft list table inet pve_webui_443
systemctl status pve-webui-443.service pveproxy
```

## Monitoring

The existing Lab Prometheus stack scrapes PVE through Tailscale in two ways:

- Debian's `prometheus-node-exporter` listens only on `100.64.0.4:9100` and
  exposes host CPU, memory, disk, network, thermal, and selected systemd data.
- `prometheus-pve-exporter` runs in the Lab monitoring stack and reads the PVE
  API using the privilege-separated `prometheus@pve!exporter` token. The user
  has only the built-in `PVEAuditor` role at `/`.

Install or refresh the maintained Node Exporter configuration with:

```bash
apt-get install -y prometheus-node-exporter
install -m 0644 prometheus-node-exporter.default \
  /etc/default/prometheus-node-exporter
systemctl restart prometheus-node-exporter
systemctl enable prometheus-node-exporter
```

Validate the PVE-side endpoint:

```bash
systemctl status prometheus-node-exporter
ss -lntp | grep 100.64.0.4:9100
curl --noproxy '*' http://100.64.0.4:9100/metrics
```

Port 8006 remains available as a recovery path. To remove only the port-443
mapping:

```bash
systemctl disable --now pve-webui-443.service
```
