# Secret Management SOP

This SOP defines how secrets are stored, generated, materialized, mounted into Docker Compose services, and documented for the `lab` host.

## Goals

- Keep real secrets out of Git.
- Use Infisical at `https://secrets.lab.skywt` as the authoritative secret inventory for lab services.
- Materialize secrets on the `lab` host only when deploying or rotating a service.
- Prefer Docker Compose secrets mounted as files under `/run/secrets` instead of environment variables.
- Make secret origin clear: generated directly in Infisical vs generated externally and then stored in Infisical.

## Scope

Treat these as secrets:

- Passwords, API keys, tokens, OAuth/OIDC client secrets, SMTP passwords, webhook tokens.
- Database DSNs when they include credentials.
- Cookie, session, JWT, encryption, signing, and registry HTTP secrets.
- TLS private keys, CA private keys, SSH private keys, WireGuard keys, backup repository passwords.
- `htpasswd`, bcrypt, or application-specific admin password hashes.
- Service-generated first-run credentials that would grant access if copied elsewhere.

Do not treat these as secrets by themselves:

- Public URLs, hostnames, container names, upstream ports, non-sensitive feature flags.
- Public certificates such as `root.crt`. The matching private keys are secrets.

## Standard layout

Infisical conventions:

- Instance URL: `https://secrets.lab.skywt`
- Project: `homelab`
- Environment: `prod`
- Service path: `/<service>`, for example `/rsshub` or `/system-monitoring`
- Secret names: uppercase snake case, for example `DATABASE_PASSWORD`, `MIHOMO_API_TOKEN`, `JWT_SECRET`

Host-side materialization conventions:

- Temporary secret files live under `/run/homelab/secrets/<service>/`.
- The directory must be created as root-only: `0700 root:root`.
- Source files should be installed as `0400 root:root` unless the service requires a different owner or mode.
- `/run/homelab/secrets` is ephemeral and is not backed up.
- Persistent runtime data remains under `/data/homelab/lab/<service>/`.
- Public, non-secret env files may live under `/data/homelab/lab/<service>/env/public.env` when committing those values is undesirable. These files must not contain secrets.

Compose conventions:

```yaml
services:
  app:
    image: example/app:latest
    secrets:
      - source: app_database_password
        target: database_password
        uid: "1000"
        gid: "1000"
        mode: 0400
    environment:
      DATABASE_PASSWORD_FILE: /run/secrets/database_password

secrets:
  app_database_password:
    file: /run/homelab/secrets/app/database_password
```

Rules:

- Prefer `_FILE` environment variables when the upstream image supports them.
- If the container runs as a non-root user, set the Compose secret `uid`, `gid`, and `mode` so that user can read the mounted file.
- If the image only accepts a secret as a normal environment variable, use a Compose shell wrapper that reads `/run/secrets/<name>` and exports it immediately before `exec` when practical; otherwise document the exception in the service README.
- Do not commit `.env` files containing real values.
- Do not put real secret values in `compose.yml`, README files, templates, or examples.
- It is acceptable to commit `.env.example` or `*.template` files with variable names and placeholder values only.

## Secret origin classes

Every secret must be classified before it is stored in Infisical.

### 1. Infisical-generated secrets

Use this class when the service only needs an opaque random value and no external system or application-specific tool imposes a format.

Examples:

- Database passwords created for a service-owned database.
- Session, cookie, JWT, or encryption secrets where the app accepts random bytes or strings.
- Docker Registry `REGISTRY_HTTP_SECRET`.
- Initial admin passwords when the app accepts a plain password and does not require a precomputed hash.
- Webhook tokens for internal-only endpoints that we define ourselves.

Generation rule:

- Generate directly in Infisical using a random value generator.
- Prefer at least 32 bytes or 32 characters of entropy.
- Use a restricted character set only when the target application documents limitations.
- Store only the resulting value in Infisical; do not also keep a copy in Git or shell history.

### 2. Externally-generated secrets

Use this class when the secret must be issued, derived, or formatted outside Infisical.

Examples:

- Third-party API keys or OAuth client secrets issued by an external provider.
- TLS private keys, CA private keys, SSH private keys, WireGuard private keys.
- `htpasswd`, bcrypt, or application-specific admin password hashes.
- Provider-specific tokens such as a Mihomo `secret` generated on the `proxy` host.
- Service-generated first-run credentials that appear in an application UI, database, file, or log.
- Infisical's own bootstrap secrets such as `ENCRYPTION_KEY`, `AUTH_SECRET`, and database password.

Generation rule:

- Generate or obtain the value using the upstream provider, official tool, or documented application procedure.
- Store the final value in Infisical under the service path.
- Document the generation source or command in the service README when it is needed for future rotation.
- Never commit the generated output, private key, hash, or provider-issued value.

## Infisical bootstrap exception

Infisical cannot depend on itself for the secrets required to start Infisical.

The Infisical stack keeps its bootstrap environment file outside Git:

- `/data/homelab/lab/infisical/env/infisical.env`

This file contains Infisical runtime secrets such as `ENCRYPTION_KEY`, `AUTH_SECRET`, the PostgreSQL password, `DB_CONNECTION_URI`, and `REDIS_URL`.

Rules:

- Keep the file `0600 root:root`.
- Back up this file securely together with Infisical PostgreSQL data.
- Without `ENCRYPTION_KEY`, restored encrypted secrets cannot be decrypted.
- Do not run or share commands that print this env file or expand it through `docker compose config` output.

## Repository helper script

`scripts/materialize-secrets.sh <service|all>` fetches service secrets from Infisical and writes Docker Compose secret source files under `/run/homelab/secrets/<service>/`.

The script requires a root-only client file on the lab host:

```bash
sudo install -d -m 0700 /data/homelab/lab/infisical
sudo install -m 0600 /dev/stdin /data/homelab/lab/infisical/client.env <<'EOF'
INFISICAL_DOMAIN=http://127.0.0.1:8080
INFISICAL_ENV=prod
INFISICAL_PROJECT_ID=<homelab-project-id>
# Preferred: Universal Auth client credentials for a read-only machine identity.
INFISICAL_CLIENT_ID=<machine-identity-client-id>
INFISICAL_CLIENT_SECRET=<machine-identity-client-secret>
# Alternative: a project-scoped access token.
# INFISICAL_TOKEN=<machine-identity-or-service-token>
EOF
```

Never commit `client.env`, print it, or paste it into issue/PR comments. Use a read-only identity or token for routine materialization.

## Deploy-time materialization

Before starting a service that needs secrets, fetch the required values from Infisical into `/run/homelab/secrets/<service>/`.

Example pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

service=my-service
project_id='<infisical-project-id>'
secret_dir="/run/homelab/secrets/${service}"

sudo install -d -m 0700 "$secret_dir"

fetch_secret() {
  local infisical_name="$1"
  local file_name="$2"
  local tmp
  tmp="$(mktemp)"

  infisical secrets get "$infisical_name" \
    --domain https://secrets.lab.skywt \
    --projectId "$project_id" \
    --env prod \
    --path "/${service}" \
    --plain >"$tmp"

  sudo install -m 0400 "$tmp" "$secret_dir/$file_name"
  rm -f "$tmp"
}

fetch_secret DATABASE_PASSWORD database_password
fetch_secret API_TOKEN api_token

cd "$HOME/homelab/services/${service}"
sudo docker compose -f compose.yml up -d
```

Operational rules:

- Do not run deploy scripts with `set -x`.
- Do not print secret values to logs.
- Prefer one deploy/materialization script per service when the service needs secrets.
- Re-run materialization and recreate/restart the container after rotating a secret.

## Validation rules

- `docker compose config` is safe to display when it shows secret file paths rather than secret values.
- For bootstrap stacks whose `env_file` contains secrets, redirect output to `/dev/null` when only syntax validation is needed:

```bash
sudo docker compose -f compose.yml config >/dev/null
```

- Review `git diff` before every commit and verify that no real secret values, hashes, or private keys are present.

## Rotation

When rotating a secret:

1. Generate the replacement according to its origin class.
2. Update the value in Infisical.
3. Materialize the new value under `/run/homelab/secrets/<service>/`.
4. Recreate or restart the affected container.
5. Verify the application and logs.
6. Revoke or remove the old value from the upstream system when applicable.
