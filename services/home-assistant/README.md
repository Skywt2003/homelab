# Home Assistant

This stack runs Home Assistant Container on the `lab` VM.

- URL: `https://home.lab.skywt`
- Runtime configuration and state: `/data/homelab/lab/home-assistant/config`
- Container networking: host mode, so local discovery protocols can use the
  `lab` VM's network interfaces.
- HTTPS: the shared Caddy container proxies to
  `host.docker.internal:8123` and terminates TLS with the internal CA.

The Git-maintained `configuration.yaml` enables the default integrations and
trusts the `lab-proxy` Docker network for Caddy's forwarded client headers. It
is mounted read-only; mutable Home Assistant state remains under the runtime
configuration directory.

## Bluetooth

The PVE host passes its Intel AX200 Bluetooth USB function (`8087:0029`) to VM
102. Bluetooth is managed by BlueZ on `lab`; Home Assistant accesses BlueZ over
the read-only `/run/dbus` mount and receives `NET_ADMIN` and `NET_RAW` for full
adapter management.

Host prerequisites:

- `lab` runs the standard Debian kernel rather than the cloud kernel, because
  the cloud kernel does not include USB or Bluetooth support.
- `bluez`, `dbus-broker`, `firmware-iwlwifi`, `rfkill`, and `usbutils` are
  installed on `lab`.
- PVE does not bind `btusb` to the AX200 while QEMU owns it. The host has
  `/etc/modprobe.d/blacklist-ax200-bluetooth-passthrough.conf` for this purpose.
- PVE VM 102 contains `usb0: host=8087:0029`.

## Secrets

This stack does not require deploy-time secrets. Home Assistant credentials and
tokens created during onboarding are stored in its runtime configuration and
must not be committed.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/home-assistant/config
sudo docker compose -f compose.yml up -d
```

Home Assistant Container does not include Home Assistant OS apps. Additional
services must be deployed as separate containers when needed.
