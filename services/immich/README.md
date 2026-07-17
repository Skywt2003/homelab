# Immich

Immich provides photo and video management at `https://photos.lab.skywt`.

## Architecture

- Caddy exposes `lab-immich:2283` through the shared `lab-proxy` network.
- Immich media data uses the Docker named volume `lab-immich-media`.
- The named volume mounts the OMV NFSv4.2 export `192.168.1.21:/Photos`.
- PostgreSQL remains on the lab host at `/data/homelab/lab/immich/postgres`.
- Machine-learning models use the local Docker volume `lab-immich-model-cache`.
- The deployed Immich release is pinned to `v3.0.3`.

Do not place PostgreSQL data on the NFS volume. Immich does not support a
network filesystem for its database.

## Secret

The PostgreSQL password is an Infisical-generated secret:

```text
Project: homelab
Environment: prod
Path: /immich
Name: DB_PASSWORD
```

It is materialized to:

```text
/run/homelab/secrets/immich/database_password
```

Both Immich and PostgreSQL read the same Compose secret through their
supported `_FILE` environment variables.

## Deploy

Materialize the database password and prepare the local database path:

```bash
cd ~/homelab
sudo ./scripts/materialize-secrets.sh immich
sudo mkdir -p /data/homelab/lab/immich/postgres
```

Validate and deploy:

```bash
cd ~/homelab/services/immich
sudo docker compose -f compose.yml config >/dev/null
sudo docker compose -f compose.yml up -d
```

The Docker daemon mounts the NFS export when `lab-immich-media` is attached
to the server container. If the export is unavailable or rejects the client,
deployment must fail rather than falling back to local media storage.

## Verify

```bash
sudo docker compose -f compose.yml ps
sudo docker volume inspect lab-immich-media
sudo docker logs --tail 100 lab-immich
curl -kI https://photos.lab.skywt
```

After the first successful start, complete the administrator onboarding in
the Immich web interface.
