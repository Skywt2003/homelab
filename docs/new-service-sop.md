# New Service SOP

This SOP describes how to add and deploy a new service on the `lab` host.

## Assumptions

- Services run with Docker Compose.
- One service stack lives under `services/<service>/`.
- Public HTTPS access is handled by the shared Caddy Docker proxy stack.
- Service routes use the shared external Docker network `lab-proxy`.
- Local lab domains use `*.lab.skywt`, currently resolved by AdGuard Home.
- Runtime data that should not be maintained in Git lives under `/data/homelab/lab`.
- Real secrets are managed by Infisical at `https://secrets.lab.skywt` and mounted into containers through Docker Compose secrets. See [Secret Management SOP](secret-management-sop.md).

## 1. Choose Service Metadata

Decide these values before creating files:

- Service name: lowercase directory name, for example `dashy`.
- Container name: `lab-<service>`, for example `lab-dashy`.
- Domain: `<name>.lab.skywt`, for example `index.lab.skywt`.
- Upstream port: the port exposed by the container inside the Docker network.
- Runtime data path, if the service needs persistent state.
- Secret inventory, if the service needs passwords, tokens, private keys, hashes, or provider credentials.

Use HTTPS URLs. Lab domains terminate TLS through Caddy's internal CA.

## 2. Create Stack Directory

Create the service directory:

```bash
mkdir -p services/<service>
```

The normal files are:

- `compose.yml`: Docker Compose stack.
- `README.md`: service purpose, domain, runtime paths, secret requirements, and deploy command.
- Service config files, when they are meant to be maintained in Git.
- Optional `.env.example` or `*.template` files with placeholders only.

Do not create or commit real `.env` files for new services.

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
- Mount secrets from `/run/homelab/secrets/<service>/...` through Docker Compose `secrets`, not as committed files.

## 4. Classify and Create Secrets

If the service needs secrets, classify each one before storing it in Infisical.

### Infisical-generated secrets

Use this class for opaque random values that do not need an external issuer or application-specific generation tool.

Examples:

- Database passwords owned by this service.
- Session, cookie, JWT, registry, webhook, or encryption secrets.
- Initial admin passwords when the application accepts a plain password.

Generate these directly in Infisical under:

```text
Project: homelab
Environment: prod
Path: /<service>
Name: UPPER_SNAKE_CASE
```

### Externally-generated secrets

Use this class when the value must be issued or formatted outside Infisical.

Examples:

- Third-party API keys and OAuth client secrets.
- TLS, CA, SSH, or WireGuard private keys.
- `htpasswd`, bcrypt, or application-specific password hashes.
- Service-generated first-run credentials.
- Provider-specific tokens such as a Mihomo `secret` generated on the `proxy` host.

Generate or obtain the value with the upstream provider, official tool, or application procedure, then store the final value in Infisical under the service path.

Document the generation source or command in `services/<service>/README.md` if future rotation depends on it.

## 5. Mount Secrets Through Docker Compose

For images that support file-based secrets, use `_FILE` style environment variables and Compose `secrets`:

```yaml
services:
  <service>:
    image: <image>:<tag>
    secrets:
      - source: <service>_database_password
        target: database_password
        uid: "1000"
        gid: "1000"
        mode: 0400
    environment:
      DATABASE_PASSWORD_FILE: /run/secrets/database_password

secrets:
  <service>_database_password:
    file: /run/homelab/secrets/<service>/database_password
```

Rules:

- Prefer `/run/secrets/<name>` inside the container.
- If the container runs as a non-root user, set the Compose secret `uid`, `gid`, and `mode` so that user can read the mounted file.
- Prefer `_FILE` variables when the upstream image supports them.
- If the image only accepts normal environment variables, prefer a Compose shell wrapper that reads `/run/secrets/<name>` and exports the variable immediately before `exec`; document the exception in the service README.
- Do not store generated secret files under the service directory.
- Public env files may be used under `/data/homelab/lab/<service>/env/public.env`, but they must contain only non-secret values.

## 6. Prepare Runtime Data

If the service needs persistent writable data, create the path on the `lab` host:

```bash
sudo mkdir -p /data/homelab/lab/<service>/<path>
sudo chown -R <uid>:<gid> /data/homelab/lab/<service>
```

Document the path in both:

- `services/<service>/README.md`
- root `README.md` under `Runtime Data`

Skip this step for read-only or stateless services.

## 7. Materialize Secrets Before Deploy

Before starting a service that declares Compose secrets, fetch the required values from Infisical into `/run/homelab/secrets/<service>/`.

Use the pattern from [Secret Management SOP](secret-management-sop.md):

```bash
sudo install -d -m 0700 /run/homelab/secrets/<service>
# Fetch each secret from Infisical into this directory with mode 0400.
```

Do not print secret values to the terminal or logs.

## 8. Update Dashy Index

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

## 9. Update Documentation

Update root `README.md`:

- Add the stack to `Layout`.
- Add runtime data paths if any.
- Add secret requirements if the service needs secrets.
- Add a deploy section or note for service-specific preparation.

Add `services/<service>/README.md` with:

- What the service does.
- Which domain exposes it.
- How Caddy exposes it.
- Runtime data paths, if any.
- Secret requirements and whether each secret is Infisical-generated or externally-generated.
- Deploy command.

## 10. Validate Compose

Before deploying, make Docker Compose render the final config:

```bash
cd ~/homelab/services/<service>
docker compose -f compose.yml config
```

For standard new services, this should show only secret file paths, not secret values.

Do not paste or share `docker compose config` output for bootstrap or legacy stacks that still use secret-bearing `env_file` entries. If only syntax validation is needed for those stacks, redirect output:

```bash
sudo docker compose -f compose.yml config >/dev/null
```

Fix any YAML, network, mount, secret path, or label issues before continuing.

## 11. Deploy

Deploy from the service directory after runtime data and required `/run/homelab/secrets/<service>/...` files exist:

```bash
cd ~/homelab/services/<service>
sudo docker compose -f compose.yml up -d
```

If the service image is not present, this may pull it from the registry.

## 12. Verify

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

## 13. Review Git Changes

Before committing, review the files changed:

```bash
git status --short
git diff
```

The expected changes for a new service are usually:

- `services/<service>/compose.yml`
- `services/<service>/README.md`
- Service config files under `services/<service>/`
- Optional `.env.example` or `*.template` files with placeholders only
- `services/dashy/conf.yml`
- root `README.md`

Avoid mixing unrelated changes into the same commit.
