# Dev Project Exposure SOP

This SOP describes how to expose a development project on the `dev` host as
`<project>.dev.skywt`.

Use this for projects under `/home/skywt/Codes` that should run as long-lived
dev servers managed by PM2, proxied by Caddy on `dev`, and resolved by AdGuard
on `lab`.

## Assumptions

- SSH target `dev` reaches the development host.
- SSH commands should load the local key first:

  ```bash
  eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
  ```

- Development projects live at `/home/skywt/Codes/<project>`.
- Domain format is `<project>.dev.skywt`.
- `*.dev.skywt` is resolved by AdGuard Home on `lab` to the `dev` host.
- Caddy runs on `dev` and terminates only plain HTTP for `*.dev.skywt` unless a
  later HTTPS plan is explicitly added.
- PM2 runs as user `skywt` on `dev`.
- When testing from `lab`, bypass shell HTTP proxies with `--noproxy '*'`.

## 1. Confirm DNS Rewrite on Lab

AdGuard Home config is maintained on `lab` at:

```text
/home/skywt/homelab/hosts/lab/dns/adguard/conf/AdGuardHome.yaml
```

The `filtering.rewrites` section should contain:

```yaml
- domain: '*.dev.skywt'
  answer: 100.64.0.5
  enabled: true
```

`100.64.0.5` is the Tailscale address of `dev`.

After editing AdGuard config, restart the container:

```bash
cd /home/skywt/homelab/hosts/lab/dns
sudo docker restart lab-adguard
```

Verify the wildcard rewrite directly against AdGuard:

```bash
host <project>.dev.skywt 100.64.0.2
host foo.dev.skywt 100.64.0.2
```

Expected result:

```text
<project>.dev.skywt has address 100.64.0.5
foo.dev.skywt has address 100.64.0.5
```

## 2. Inspect the Project on Dev

Connect to `dev` and inspect the project:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev 'cd /home/skywt/Codes/<project> && pwd && sed -n "1,220p" package.json'
```

Identify:

- package manager (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, etc.)
- dev script, usually `dev`
- dev server port, for example `next dev -p 4000`
- environment files, for example `.env`

If tooling is missing on a fresh `dev` host, install it first:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev 'sudo apt-get update && sudo apt-get install -y caddy nodejs npm && sudo npm install -g pm2 pnpm@10'
```

Use `pnpm@10` with Debian Node 20. Avoid installing `pnpm@11` unless `dev` has
Node 22.13 or newer.

## 3. Install Project Dependencies

For pnpm projects:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev 'cd /home/skywt/Codes/<project> && CI=true pnpm install --frozen-lockfile'
```

Notes:

- `CI=true` lets pnpm recreate an existing `node_modules` directory
  non-interactively.
- Review warnings, but build-script approval warnings are not necessarily fatal
  for a dev server. Verify with PM2 logs and HTTP checks.

## 4. Start the Dev Server with PM2

Use a PM2 process name that matches the project:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev '
  set -e
  cd /home/skywt/Codes/<project>
  pm2 delete <project> >/dev/null 2>&1 || true
  pm2 start pnpm --name <project> -- dev
  pm2 save
  pm2 list
  pm2 logs <project> --lines 80 --nostream
'
```

The logs should show the dev server is ready and listening on the expected port.

For example, Next.js should show something like:

```text
Local:   http://localhost:<port>
Network: http://<dev-ip>:<port>
Ready
```

## 5. Ensure PM2 Starts on Boot

If PM2 startup has not been installed yet:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev 'sudo env PATH=$PATH:/usr/local/bin:/usr/bin pm2 startup systemd -u skywt --hp /home/skywt && pm2 save'
```

If the `pm2-skywt` service was just created after a manual PM2 daemon was
already running, systemd may initially fail to take ownership of the existing
daemon. Fix it by letting systemd resurrect the saved process list:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev '
  set -e
  pm2 save
  pm2 kill
  sudo systemctl reset-failed pm2-skywt
  sudo systemctl start pm2-skywt
  systemctl is-active pm2-skywt
  pm2 list
'
```

Expected:

```text
active
```

and the project process is `online`.

## 6. Add Caddy Reverse Proxy on Dev

Edit `/etc/caddy/Caddyfile` on `dev`. Add a host-specific HTTP site block:

```caddyfile
http://<project>.dev.skywt {
	reverse_proxy 127.0.0.1:<port>
}
```

Keep a fallback `:80` block if desired:

```caddyfile
:80 {
	root * /usr/share/caddy
	file_server
}
```

Apply and validate:

```bash
eval "$(keychain --noask --eval ~/.ssh/id_ed25519)"
ssh dev '
  set -e
  sudo caddy fmt --overwrite /etc/caddy/Caddyfile
  sudo caddy validate --config /etc/caddy/Caddyfile
  sudo systemctl reload caddy
  systemctl is-enabled caddy
  systemctl is-active caddy
'
```

Expected:

```text
enabled
active
```

## 7. Verify from Lab

Do not use `curl --resolve` for the final test. Test actual DNS and HTTP access.

Because the shell environment may define `HTTP_PROXY`/`HTTPS_PROXY`, bypass
proxies for internal checks:

```bash
host <project>.dev.skywt 100.64.0.2
getent hosts <project>.dev.skywt
curl --noproxy '*' -I --max-time 20 http://<project>.dev.skywt
curl --noproxy '*' -L --max-time 30 -s -o /tmp/<project>.dev.skywt.html \
  -w '%{http_code} %{content_type} %{remote_ip} %{url_effective}\n' \
  http://<project>.dev.skywt
```

Expected:

- DNS returns `100.64.0.5`.
- `curl` reaches `100.64.0.5`.
- HTTP status is an application-appropriate success or redirect, for example:
  - `200 text/html`
  - `307` followed by `200` for auth redirects.

If direct `curl` fails but `curl --resolve` works, do not treat that as success:
fix DNS routing or AdGuard rewrites first.

## 8. Troubleshooting

### Lab Resolves Through a Proxy

If `curl` returns a proxy-looking response such as `503` with
`Proxy-Connection`, rerun with:

```bash
curl --noproxy '*' http://<project>.dev.skywt
```

### DNS Returns NXDOMAIN

Check AdGuard directly:

```bash
host <project>.dev.skywt 100.64.0.2
```

If direct AdGuard lookup fails:

1. Inspect the rewrite in `AdGuardHome.yaml`.
2. Restart `lab-adguard`.
3. Check container status and logs:

   ```bash
   sudo docker ps -a --filter name=lab-adguard
   sudo docker logs --tail 120 lab-adguard
   ```

If direct AdGuard lookup works but system lookup fails:

```bash
sudo resolvectl flush-caches
resolvectl query <project>.dev.skywt
resolvectl status
```

### Caddy Returns the Wrong Site

Verify the Caddy site block uses the exact host:

```caddyfile
http://<project>.dev.skywt
```

Then validate and reload:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

### PM2 Process Is Online but HTTP Fails

Check logs and port binding on `dev`:

```bash
pm2 logs <project> --lines 100 --nostream
ss -lntp | grep <port>
curl -I http://127.0.0.1:<port>
```

### `pm2-skywt.service` Fails with `Result: protocol`

This usually means systemd tried to adopt a PM2 daemon that was started
manually outside the service cgroup. Save, kill, and restart through systemd:

```bash
pm2 save
pm2 kill
sudo systemctl reset-failed pm2-skywt
sudo systemctl start pm2-skywt
```

