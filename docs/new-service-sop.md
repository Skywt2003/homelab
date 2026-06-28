# New Service SOP

This SOP describes how to add and deploy a new service on the `lab` host.

## Assumptions

- Services run with Docker Compose.
- One service stack lives under `services/<service>/`.
- Public HTTPS access is handled by the shared Caddy Docker proxy stack.
- Service routes use the shared external Docker network `lab-proxy`.
- Local lab domains use `*.lab.skywt`, currently resolved by AdGuard Home.
- Runtime data that should not be maintained in Git lives under `/data/homelab/lab`.

## 1. Choose Service Metadata

Decide these values before creating files:

- Service name: lowercase directory name, for example `dashy`.
- Container name: `lab-<service>`, for example `lab-dashy`.
- Domain: `<name>.lab.skywt`, for example `index.lab.skywt`.
- Upstream port: the port exposed by the container inside the Docker network.
- Runtime data path, if the service needs persistent state.

Use HTTPS URLs. Lab domains terminate TLS through Caddy's internal CA.

## 2. Create Stack Directory

Create the service directory:

```bash
mkdir -p services/<service>
```

The normal files are:

- `compose.yml`: Docker Compose stack.
- `README.md`: service purpose, domain, runtime paths, and deploy command.
- Service config files, when they are meant to be maintained in Git.

## 3. Write Compose File

Use this baseline pattern:

```yaml
services:
  <service>:
    image: <image>:<tag>
    container_name: lab-<service>
    restart: unless-stopped
    networks:
      - lab-proxy
    labels:
      caddy: <domain>.lab.skywt
      caddy.tls: internal
      caddy.reverse_proxy: "{{upstreams <port>}}"

networks:
  lab-proxy:
    external: true
```

Rules:

- Do not publish HTTP ports directly unless the service must bypass Caddy.
- Put the service on `lab-proxy` so Caddy can reach it.
- Use Docker labels for Caddy routing.
- Mount Git-maintained config files from the service directory.
- Mount mutable runtime data from `/data/homelab/lab/<service>/...`.

## 4. Prepare Runtime Data

If the service needs persistent writable data, create the path on the `lab` host:

```bash
sudo mkdir -p /data/homelab/lab/<service>/<path>
sudo chown -R <uid>:<gid> /data/homelab/lab/<service>
```

Document the path in both:

- `services/<service>/README.md`
- root `README.md` under `Runtime Data`

Skip this step for read-only or stateless services.

## 5. Update Dashy Index

Add the new service to `services/dashy/conf.yml`:

```yaml
- title: <Display Name>
  description: <Short purpose>
  icon: <icon>
  url: https://<domain>.lab.skywt
  statusCheck: true
```

For infrastructure components without a web UI, add a non-clickable item and set `statusCheck: false`.

After changing Dashy config, reload Dashy:

```bash
cd ~/homelab/services/dashy
sudo docker compose -f compose.yml restart dashy
```

## 6. Update Documentation

Update root `README.md`:

- Add the stack to `Layout`.
- Add runtime data paths if any.
- Add a deploy section for the service.

Add `services/<service>/README.md` with:

- What the service does.
- Which domain exposes it.
- How Caddy exposes it.
- Runtime data paths, if any.
- Deploy command.

## 7. Validate Compose

Before deploying, make Docker Compose render the final config:

```bash
cd ~/homelab/services/<service>
docker compose -f compose.yml config
```

Fix any YAML, network, mount, or label issues before continuing.

## 8. Deploy

Deploy from the service directory:

```bash
cd ~/homelab/services/<service>
sudo docker compose -f compose.yml up -d
```

If the service image is not present, this may pull it from the registry.

## 9. Verify

Check container status:

```bash
sudo docker compose -f compose.yml ps
```

Check logs:

```bash
sudo docker logs --tail 80 lab-<service>
```

Confirm Caddy loaded the route:

```bash
sudo docker logs --tail 120 lab-caddy
```

Expected Caddy output includes a generated route like:

```text
<domain>.lab.skywt {
	tls internal
	reverse_proxy <container-ip>:<port>
}
```

Verify the route from inside the Caddy container:

```bash
sudo docker exec lab-caddy wget -S -O- --no-check-certificate --header 'Host: <domain>.lab.skywt' https://127.0.0.1
```

Expected result:

- HTTP status is `200`, `301`, `302`, or another valid status for that app.
- The response is served by Caddy.
- The upstream app logs do not show startup errors.

If host-level `curl https://<domain>.lab.skywt` fails but the Caddy-container check passes, check local DNS, certificate trust, or shell proxy settings before changing the service config.

## 10. Review Git Changes

Before committing, review the files changed:

```bash
git status --short
git diff
```

The expected changes for a new service are usually:

- `services/<service>/compose.yml`
- `services/<service>/README.md`
- Service config files under `services/<service>/`
- `services/dashy/conf.yml`
- root `README.md`

Avoid mixing unrelated changes into the same commit.
