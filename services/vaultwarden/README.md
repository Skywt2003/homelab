# Vaultwarden

Vaultwarden is the self-hosted Bitwarden-compatible password manager exposed at
`https://passwords.lab.skywt` through the shared Caddy proxy.

## Runtime data

- `/data/homelab/lab/vaultwarden/data`: SQLite database, attachments, keys, and
  other mutable Vaultwarden state.

The container does not publish a host port. Caddy reaches port `80` over the
external `lab-proxy` Docker network and terminates HTTPS with the lab internal
CA.

## First account and registration

Registration is disabled with `SIGNUPS_ALLOWED` set to `"false"`. Existing users
can continue to sign in. Temporarily enable it only when intentionally creating
a new account, then disable it and redeploy the stack again.

The admin page is enabled at `https://passwords.lab.skywt/admin`. Its login
password is stored in the Vaultwarden login item for that URL. Vaultwarden
receives only an Argon2id PHC hash, stored in Infisical under project `homelab`,
environment `prod`, path `/vaultwarden`, secret name `ADMIN_TOKEN`.

The hash is materialized to
`/run/homelab/secrets/vaultwarden/admin_token` and injected immediately before
the Vaultwarden process starts; it must never be committed or printed.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/vaultwarden/data
cd ~/homelab/services/vaultwarden
sudo ../../scripts/materialize-secrets.sh vaultwarden
sudo docker compose -f compose.yml up -d
```

Validate with:

```bash
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-vaultwarden
curl --noproxy '*' --cacert /data/homelab/lab/caddy/data/caddy/pki/authorities/local/root.crt \
  https://passwords.lab.skywt/alive
```
