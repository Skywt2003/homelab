# MoviePilot

MoviePilot provides media subscription and library automation at
`https://media.lab.skywt`. The same stack runs qBittorrent at
`https://torrent.lab.skywt` as its download client.

Use the stack only with content and trackers that you are authorized to use.

## Architecture

- Caddy exposes MoviePilot on container port `3000` and qBittorrent on
  container port `8080` through the shared `lab-proxy` network.
- MoviePilot talks to qBittorrent over the private `lab-moviepilot` network.
- Both containers mount the same Docker named volume, `lab-moviepilot-media`,
  at `/media`.
- The named volume mounts the OMV NFSv4.2 export `192.168.1.21:/Media`.
- Both mounts use Compose `volume.nocopy` so Docker does not try to change the
  root-squashed NFS export's ownership while creating the containers.
- MoviePilot configuration and its browser runtime remain local to `lab` at
  `/data/homelab/lab/moviepilot/config` and
  `/data/homelab/lab/moviepilot/core`.
- qBittorrent configuration remains local to `lab` at
  `/data/homelab/lab/moviepilot/qbittorrent`.
- The BitTorrent peer port is published as TCP and UDP `51413`; the two web
  ports are reachable only through Caddy.
- The stack does not mount the Docker socket. Update and restart the
  containers through Docker Compose rather than MoviePilot's built-in Docker
  restart integration.

MoviePilot is pinned to `2.14.5`, and the LinuxServer.io qBittorrent image is
pinned to `5.2.3_v2.0.13-ls468`. MoviePilot application self-update is
disabled; update the pinned image deliberately through this Compose file.
MoviePilot resource updates remain enabled.

## Media Layout

Prepare this layout on the NAS export:

```text
/Media
├── downloads
│   ├── incomplete
│   ├── movie
│   └── tv
└── library
    ├── movie
    └── tv
```

Both containers must use the same paths below. Do not replace the single
`/media` volume with separate download and library mounts, because that would
prevent hard-link based organization.

| Purpose | Container path |
| --- | --- |
| Incomplete downloads | `/media/downloads/incomplete` |
| Movie downloads | `/media/downloads/movie` |
| TV downloads | `/media/downloads/tv` |
| Movie library | `/media/library/movie` |
| TV library | `/media/library/tv` |

The NFS directories must be writable by numeric UID/GID `1000:1000`. Both
containers run with `PUID=1000`, `PGID=1000`, and `UMASK=002`.

## Credentials

No real credential is stored in this repository or passed in the Compose
file.

MoviePilot generates a temporary administrator password and API token on its
first start. qBittorrent prints a temporary password for the `admin` user on
first start. Retrieve them from the first-start logs, log in, and immediately
replace them with strong final values.

Keep the final values in Infisical under project `homelab`, environment
`prod`, path `/moviepilot`:

```text
MOVIEPILOT_ADMIN_PASSWORD
MOVIEPILOT_API_TOKEN
QBITTORRENT_PASSWORD
```

These values are application-managed after onboarding rather than Compose
startup secrets, so this stack does not use files under
`/run/homelab/secrets`.

## Prepare

On the NAS, create the media layout and make it writable by the service
UID/GID. The exact commands depend on how the OMV shared folder is backed and
managed; verify the resulting numeric ownership is `1000:1000`.

On the `lab` host, prepare local state:

```bash
sudo install -d -m 0775 -o 1000 -g 1000 \
  /data/homelab/lab/moviepilot/config \
  /data/homelab/lab/moviepilot/core \
  /data/homelab/lab/moviepilot/qbittorrent
```

The NFS export must be reachable before deployment. The Docker-managed NFS
volume intentionally causes deployment to fail if the NAS is unavailable,
instead of silently writing media into a local directory.

## Deploy

Validate and deploy:

```bash
cd ~/homelab/services/moviepilot
sudo docker compose -f compose.yml config >/dev/null
sudo docker compose -f compose.yml up -d
```

Inspect the first-start credentials without copying them into shell history:

```bash
sudo docker logs lab-moviepilot
sudo docker logs lab-moviepilot-qbittorrent
```

After logging in, set the final passwords and API token, then configure:

1. In qBittorrent, set the default save path to `/media/downloads` and the
   incomplete path to `/media/downloads/incomplete`.
2. In MoviePilot, add qBittorrent with URL `http://qbittorrent:8080` and its
   final username and password.
3. Add the MoviePilot download paths under `/media/downloads` and library
   paths under `/media/library`.
4. Select hard link as the organization mode and enable automatic processing
   of completed downloads.
5. If inbound peer connectivity is required, forward TCP and UDP port `51413`
   from the upstream router to the `lab` host.

## Verify

```bash
sudo docker compose -f compose.yml ps
sudo docker volume inspect lab-moviepilot-media
sudo docker logs --tail 100 lab-moviepilot
sudo docker logs --tail 100 lab-moviepilot-qbittorrent
curl -kI https://media.lab.skywt
curl -kI https://torrent.lab.skywt
```

Create a small authorized test download and confirm that MoviePilot can make
a hard link from `/media/downloads` into `/media/library`. On the NAS, the
source and organized file should have the same inode number.

Also test an unavailable NAS before relying on unattended boot recovery. If
Docker does not retry the NFS mount after the NAS returns, run the Compose
`up -d` command again; a dedicated NAS-dependent systemd recovery unit can be
added separately after that behavior is confirmed.
