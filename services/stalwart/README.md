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

mosdns provides:

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

## Application integrations

Applications use `mail.lab.skywt:2525` without SMTP authentication or TLS.
Where a recipient is required for system notifications, it is
`me@skywt.internal`.

| Service URL | Sender | Configuration storage |
| --- | --- | --- |
| `passwords.lab.skywt` | `passwords@skywt.internal` | Compose environment |
| `git.lab.skywt` | `git@skywt.internal` | Compose environment |
| `grafana.lab.skywt` | `grafana@skywt.internal` | Compose environment |
| `secrets.lab.skywt` | `secrets@skywt.internal` | Infisical runtime env file |
| `photos.lab.skywt` | `photos@skywt.internal` | Immich system configuration |
| `ai-api.lab.skywt` | `ai-api@skywt.internal` | New API options database |
| `books.lab.skywt` | `books@skywt.internal` | Calibre-Web app database |
| `home.lab.skywt` | `home@skywt.internal` | Home Assistant SMTP config entry |
| `alertmanager.lab.skywt` | `alertmanager@skywt.internal` | Alertmanager configuration |
| `torrent.lab.skywt` | `torrent@skywt.internal` | qBittorrent preferences |
| `notify.lab.skywt` | `notify@skywt.internal` | Apprise runtime configuration |

Prometheus sends notifications through Alertmanager. MoviePilot itself does not
provide an SMTP notification channel. Backrest supports email through a
Shoutrrr hook attached to a repository or backup plan; configure
`backups@skywt.internal` when a plan is created.

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
