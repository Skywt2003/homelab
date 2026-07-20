# Android scrcpy Remote Control

This stack runs scrcpy against the Android phone passed through from PVE to the
`lab` VM, and exposes the scrcpy window through TigerVNC and noVNC.

- URL: `https://phone.lab.skywt/vnc.html?autoconnect=true&resize=scale&reconnect=true&show_dot=false`
- Short URL: `https://phone.lab.skywt` redirects to the URL above.
- Android serial: `9c9c03f`
- PVE VM: `102` (`lab`)
- PVE USB mapping: `usb1: host=6-1`
- TLS: Caddy internal CA

The stack uses two containers:

- `lab-android-adb` owns USB access and runs the ADB server on an isolated
  Docker network.
- `lab-android-scrcpy` runs scrcpy, TigerVNC, and noVNC. Only noVNC port 6080 is
  reachable by Caddy over `lab-proxy`.

ADB is not exposed to the LAN or tailnet. The ADB server and scrcpy client talk
over the internal `android-scrcpy-adb` network.

Run administrative ADB commands inside the ADB container so a second host ADB
server does not compete for the USB interface:

```bash
sudo docker exec lab-android-adb adb devices -l
sudo docker exec lab-android-adb adb -s 9c9c03f shell
```

## Runtime Data

- `/data/homelab/lab/android-scrcpy/adb`: persistent ADB host key used by the
  container. Treat this directory as sensitive runtime state.

The first deployment copies the already-authorized key from
`/home/skywt/.android` into this runtime directory. If the key is replaced, the
phone must approve the new USB debugging fingerprint.

## Secret

`VNC_PASSWORD` is an Infisical-generated secret:

- Project: `homelab`
- Environment: `prod`
- Path: `/android-scrcpy`
- Name: `VNC_PASSWORD`
- Materialized file: `/run/homelab/secrets/android-scrcpy/vnc_password`

TigerVNC authentication uses at most the first eight password characters. The
password itself remains in Infisical and the root-only materialized file; it is
not committed to this repository. Transport security is provided by Caddy
HTTPS, and access should remain limited to trusted LAN or Tailscale clients.

Materialize the secret without printing it:

```bash
sudo ./scripts/materialize-secrets.sh android-scrcpy
```

To display the VNC password interactively on the trusted `lab` terminal:

```bash
sudo cat /run/homelab/secrets/android-scrcpy/vnc_password
```

## Deploy

```bash
sudo install -d -m 0700 -o root -g root /data/homelab/lab/android-scrcpy/adb
sudo install -m 0600 /home/skywt/.android/adbkey /data/homelab/lab/android-scrcpy/adb/adbkey
sudo install -m 0644 /home/skywt/.android/adbkey.pub /data/homelab/lab/android-scrcpy/adb/adbkey.pub
sudo ./scripts/materialize-secrets.sh android-scrcpy
adb kill-server
cd services/android-scrcpy
sudo docker compose -f compose.yml up -d --build
```

## Connect from iOS

1. Connect the iPhone or iPad to the lab tailnet with Tailscale.
2. Install and trust the lab internal CA if it is not already trusted. The
   profile is available from `https://ca.lab.skywt`.
3. Open the noVNC URL above in Safari.
4. Enter the VNC password materialized on `lab`.
5. Use taps and drags in the canvas to control Android. Complex multi-touch
   gestures may not map perfectly through VNC.

The Android secure lock screen is not bypassed. A PIN, password, or pattern must
still be entered manually on the phone when Android requires it.

The VNC desktop has a fixed portrait geometry and rejects remote resize
requests. noVNC must use `resize=scale`: `resize=remote` can otherwise move the
scrcpy window outside a browser-sized desktop and leave only one corner visible.

This image applies a dedicated direct-touch profile to noVNC. A stationary
single-finger touch is converted to a held primary mouse button after 150 ms,
so scrcpy receives Android touch-down, hold, and touch-up events instead of
noVNC's stock right-click gesture. Hold for roughly one second to trigger an
Android long press. The former touch-hold-as-right-click gesture is therefore
not available; use `Alt+B` for Android BACK.

## Validate

```bash
sudo docker compose -f compose.yml config >/dev/null
sudo docker compose -f compose.yml ps
sudo docker logs --tail 100 lab-android-adb
sudo docker logs --tail 100 lab-android-scrcpy
curl -kI 'https://phone.lab.skywt/vnc.html'
```
