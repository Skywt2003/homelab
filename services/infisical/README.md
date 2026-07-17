# Infisical

This stack runs Infisical for `secrets.lab.skywt`.

Infisical is the homelab secret management platform. It is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime state and deployment secrets are stored outside this Git repository:

- `/data/homelab/lab/infisical/env/infisical.env`: Infisical runtime environment, including encryption and database secrets.
- `/data/homelab/lab/infisical/postgres`: PostgreSQL data. This contains Infisical users, projects, configuration, and encrypted secrets.
- `/data/homelab/lab/infisical/redis`: Redis cache and job queue data.

Back up both PostgreSQL data and `ENCRYPTION_KEY` from `infisical.env`. Without the encryption key, restored database secrets cannot be decrypted.

## Bootstrap Secrets

Infisical is the exception to the normal secret flow because it cannot fetch the secrets required to start itself from Infisical.

The following are externally-generated bootstrap secrets and live only in `/data/homelab/lab/infisical/env/infisical.env` plus secure backups:

- `ENCRYPTION_KEY`
- `AUTH_SECRET`
- `POSTGRES_PASSWORD`
- `DB_CONNECTION_URI`

Keep the file `0600 root:root`. Do not paste `docker compose config` output for this stack because Compose expands `env_file` values into the rendered config.

For secrets managed for other lab services, use Infisical project `homelab`, environment `prod`, path `/<service>`, and the [Secret Management SOP](../../docs/secret-management-sop.md).

## Deploy

Prepare the runtime directories and environment file on the lab host, then deploy:

```bash
cd ~/homelab/services/infisical
sudo docker compose -f compose.yml up -d
```

Verify the service:

```bash
sudo docker compose -f compose.yml ps
sudo docker logs --tail 100 lab-infisical
sudo docker exec lab-caddy wget -S -O- --no-check-certificate --header 'Host: secrets.lab.skywt' https://127.0.0.1/api/status
```

After first start, open `https://secrets.lab.skywt` and create the first user. The first signed-up user becomes the instance administrator.
