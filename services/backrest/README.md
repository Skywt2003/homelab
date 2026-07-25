# Backrest

This stack runs Backrest and its bundled restic CLI at
`https://backups.lab.skywt`.

Backrest is exposed only through the shared Caddy reverse proxy. No host port
is published. The image is pinned to `v1.13.0`.

## Storage

The OMV `Backups` shared folder on `nas` is available in two ways:

- Authenticated, writable Samba share `Backups` for clients that need SMB.
- NFSv4.2 export `192.168.1.21:/Backups`, restricted to the `lab` host at
  `192.168.1.236`.

The NFS export is mounted by the `lab` host at `/mnt/backups` and bind-mounted
into the container at `/repos`. Backrest repositories created later should use
paths below `/repos`. The initial deployment intentionally does not create a
restic repository or backup plan.

The host mount is declared in `/etc/fstab` outside this repository:

```fstab
192.168.1.21:/Backups /mnt/backups nfs rw,hard,nfsvers=4.2,proto=tcp,resvport,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=0 0 0
```

The OMV NFS export uses `all_squash`, mapping writes to numeric UID/GID
`1000:100`. This matches the existing Photos and Books export pattern and
prevents container root from becoming NAS root.

Backrest's local application state remains on `lab`:

- `/data/homelab/lab/backrest/config`
- `/data/homelab/lab/backrest/data`
- `/data/homelab/lab/backrest/cache`
- `/data/homelab/lab/backrest/tmp`

## First Login and Secrets

On the first visit, complete Backrest's setup wizard and create its UI account.
No initial credential is stored in Compose or Git. Store the final account and
future restic repository passwords in Infisical under the `/backrest` path.

The generated Backrest configuration is runtime state under
`/data/homelab/lab/backrest/config`; it can contain repository credentials and
must not be committed.

## Deploy

The host requires the `nfs-common` package and an active `/mnt/backups` mount.

```bash
sudo install -d -m 0755 /mnt/backups
sudo install -d -m 0750 \
  /data/homelab/lab/backrest/config \
  /data/homelab/lab/backrest/data \
  /data/homelab/lab/backrest/cache \
  /data/homelab/lab/backrest/tmp
sudo mount /mnt/backups

cd ~/homelab/services/backrest
sudo docker compose -f compose.yml config >/dev/null
sudo docker compose -f compose.yml up -d
```

## Verify

```bash
findmnt /mnt/backups
sudo docker compose -f compose.yml ps
sudo docker logs --tail 100 lab-backrest
curl --noproxy '*' -kI https://backups.lab.skywt/
```

The container should report `healthy`, HTTPS should return a successful HTTP
response, and `/repos` inside the container should be the NFS-backed directory.
