# Stalwart Mail

This stack provides the internal-only mail service at `mail.lab.skywt` for the
mail domain `skywt.internal`. Stalwart's internal canonical hostname is
`mail.skywt.internal`, while clients and the web UI use `mail.lab.skywt`.

## Network policy

- `100.64.0.2:587`: authenticated SMTP submission with STARTTLS.
- `100.64.0.2:993`: authenticated IMAP over implicit TLS.
- `100.64.0.2:2525`: unauthenticated SMTP for applications on the Tailscale
  network. It accepts only a `skywt.internal` envelope sender and local
  `@skywt.internal`
  recipients.
- No SMTP or IMAP port is published on the LAN or public interfaces.
- Stalwart relay is disabled, so mail for non-local domains is rejected instead
  of being queued for Internet delivery.
- Spam classification is disabled because this deployment has no public inbound
  SMTP path; trusted internal notifications therefore arrive in `INBOX`.

The HTTPS administration and account UI is exposed through the shared Caddy
reverse proxy at `https://mail.lab.skywt`.

## TLS

Stalwart obtains the certificate used by SMTP and IMAP from the existing Caddy
internal ACME server at `https://acme.lab.skywt/acme/local/directory`. The
combined trust bundle mounted into the container contains the host system roots
plus Caddy's public root certificate; it does not contain a private key.

## DNS

AdGuard Home provides:

- `mail.lab.skywt A 100.64.0.2` through the existing `*.lab.skywt` rewrite.
- `skywt.internal MX 10 mail.lab.skywt.`

## Runtime data

- `/data/homelab/lab/stalwart/etc`
- `/data/homelab/lab/stalwart/data`
- `/data/homelab/lab/stalwart/tls/ca-certificates.crt`

The `etc` and `data` directories must be owned by Stalwart's container user,
UID/GID `2000:2000`. Back up both directories together.

## Accounts and secrets

The internal directory stores password hashes in Stalwart's data store. Plain
credentials are kept in Infisical at the project root using the
`STALWART_*_PASSWORD` names for recovery and client setup; they are not
committed or mounted into the container at runtime.

## Deploy

```bash
sudo install -d -m 0750 -o 2000 -g 2000 \
  /data/homelab/lab/stalwart/{etc,data}
sudo install -d -m 0755 -o root -g root \
  /data/homelab/lab/stalwart/tls
cat /etc/ssl/certs/ca-certificates.crt \
  /data/homelab/lab/caddy/data/caddy/pki/authorities/local/root.crt \
  | sudo tee /data/homelab/lab/stalwart/tls/ca-certificates.crt >/dev/null
sudo chmod 0644 /data/homelab/lab/stalwart/tls/ca-certificates.crt

cd ~/homelab/services/stalwart
sudo docker compose -f compose.yml up -d
```
