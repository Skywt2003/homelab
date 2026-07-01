# Secret Governance Audit - 2026-06-30 UTC

This audit records the outcome of the Infisical and Docker Compose secrets migration for the `lab` host.

## Scope

The migration targeted all repository-managed services under `services/` and specifically remediated services that previously used repo-local `.env` files or inline secret-like values:

- `services/docker-registry`
- `services/nexus-admin`
- `services/rsshub`
- `services/system-monitoring`

Infisical itself remains a bootstrap exception. Its runtime bootstrap file stays outside Git at `/data/homelab/lab/infisical/env/infisical.env`.

## Infisical paths

Secrets were imported and verified in these Infisical paths under project `homelab`, environment `prod`:

| Path | Secret names |
| --- | --- |
| `/docker-registry` | `REGISTRY_HTTP_SECRET` |
| `/nexus-admin` | `ADMIN_PASSWORD`, `RESEND_API_KEY`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `SUPABASE_SECRET_KEY` |
| `/rsshub` | `TWITTER_AUTH_TOKEN` |
| `/system-monitoring` | `MIHOMO_API_TOKEN` |

The one-time legacy import files under `/data/homelab/lab/legacy-secrets` were removed after import, materialization, service restart, and verification.

## Runtime materialization

Secrets are materialized from Infisical to Docker Compose secret source files under `/run/homelab/secrets`:

```text
/run/homelab/secrets/docker-registry/http_secret
/run/homelab/secrets/nexus-admin/admin_password
/run/homelab/secrets/nexus-admin/resend_api_key
/run/homelab/secrets/nexus-admin/s3_access_key_id
/run/homelab/secrets/nexus-admin/s3_secret_access_key
/run/homelab/secrets/nexus-admin/supabase_secret_key
/run/homelab/secrets/rsshub/twitter_auth_token
/run/homelab/secrets/system-monitoring/mihomo_api_token
```

Non-secret public env files live outside Git:

```text
/data/homelab/lab/nexus-admin/env/public.env
/data/homelab/lab/rsshub/env/public.env
```

## Verification summary

Commands were run without printing secret values.

- Infisical read verification passed for all migrated secret names.
- No repo-local `.env`, `.env.local`, or `*.env` files were found under `services/`.
- `/data/homelab/lab/legacy-secrets` contained no files after cleanup.
- `docker compose -f compose.yml config` passed for every stack under `services/`.
- `git diff --check` passed.
- Pattern scan did not find committed private keys, obvious provider tokens, or inline values for the migrated secret names.
- Docker inspect showed no migrated secret keys in container `Config.Env` for:
  - `lab-docker-registry`
  - `lab-nexus-admin`
  - `lab-rsshub`
  - `lab-mihomo-exporter`
- Docker inspect showed no repo-local `.env` mounts for those containers.

## Service access smoke test

Caddy-local HTTPS smoke tests returned:

| URL | HTTP status |
| --- | --- |
| `https://index.lab.skywt` | 200 |
| `https://dns.lab.skywt` | 302 |
| `https://grafana.lab.skywt` | 302 |
| `https://prometheus.lab.skywt` | 302 |
| `https://alertmanager.lab.skywt` | 200 |
| `https://archive.lab.skywt` | 302 |
| `https://git.lab.skywt` | 200 |
| `https://rsshub.lab.skywt` | 200 |
| `https://ca.lab.skywt` | 200 |
| `https://docker.lab.skywt/v2/` | 200 |
| `https://secrets.lab.skywt/api/status` | 200 |
| `https://blog-admin.lab.skywt` | 307 |
| `https://ai-api.lab.skywt` | 200 |
| `https://notify.lab.skywt` | 200 |

Redirect statuses are expected for services that send unauthenticated users to login or setup routes.

## Notes

- Docker Compose emits warnings that `uid`, `gid`, and `mode` are ignored for file-backed secrets outside Swarm. Source files under `/run/homelab/secrets` are still managed with restrictive host permissions where practical.
- Some upstream images only accept secrets through environment variables. For those, Compose mounts Docker secret files and uses an entrypoint/command wrapper to export the environment variable immediately before the original process starts.
- The Infisical client credential file `/data/homelab/lab/infisical/client.env` is outside Git and should be kept `0600 root:root`. After migration, prefer a read-only identity for routine `materialize-secrets.sh` runs.
