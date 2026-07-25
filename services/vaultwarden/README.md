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

Registration is enabled initially so the first account can be created. After
creating and verifying the intended account, set `SIGNUPS_ALLOWED` to `"false"`
in `compose.yml` and redeploy the stack. Existing users can continue to sign in.

No application secret is required for this initial deployment. The Vaultwarden
admin page is not enabled because no admin token is configured.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/vaultwarden/data
cd ~/homelab/services/vaultwarden
sudo docker compose -f compose.yml up -d
```

Validate with:

```bash
sudo docker compose -f compose.yml ps
sudo docker logs --tail 80 lab-vaultwarden
curl --noproxy '*' --cacert /data/homelab/lab/caddy/data/caddy/pki/authorities/local/root.crt \
  https://passwords.lab.skywt/alive
```
