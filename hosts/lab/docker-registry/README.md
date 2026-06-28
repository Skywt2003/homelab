# Docker Registry

This stack runs a Docker Registry for `docker.lab.skywt`.

The registry API is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Runtime image storage is stored outside this Git repository:

- `/data/homelab/lab/docker-registry/data`

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/docker-registry/data
cd ~/homelab/hosts/lab/docker-registry
sudo docker compose -f compose.yml up -d
```

## Usage

Docker clients need to use the lab DNS resolver and trust the lab Caddy internal CA before pushing or pulling over HTTPS. The CA guide is served at `https://ca.lab.skywt`, and the root certificate is available at `https://ca.lab.skywt/root.crt`.

On Linux Docker hosts, install the CA for this registry name:

```bash
sudo mkdir -p /etc/docker/certs.d/docker.lab.skywt
curl -fsSL -k https://ca.lab.skywt/root.crt | sudo tee /etc/docker/certs.d/docker.lab.skywt/ca.crt >/dev/null
sudo systemctl restart docker
```

Then push and pull images with the registry hostname:

```bash
docker tag alpine:latest docker.lab.skywt/alpine:latest
docker push docker.lab.skywt/alpine:latest
docker pull docker.lab.skywt/alpine:latest
```

This registry is intended for lab-internal use and does not publish port `5000` directly on the host. It is currently unauthenticated, so any client with network access and trust for the lab CA can push and pull images.
