# Calibre-Web

This stack runs Calibre-Web for `books.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Calibre-Web uses the existing Calibre library as its default book library, with
the Calibre `metadata.db` expected at `/books/metadata.db` inside the container.
The runtime Calibre-Web app database should have `config_calibre_dir` set to
`/books`.

Runtime state is stored outside this Git repository:

- Local application configuration: `/data/homelab/lab/calibre-web/config`
- Book library: the OMV `Books` shared folder on `nas`, mounted from the NFSv4.2
  export `192.168.1.21:/Books` through the Docker volume
  `lab-calibre-web-books`

The same `Books` shared folder is also published by OMV over authenticated,
writable Samba as `Books`. NFS access is restricted to the `lab` host at
`192.168.1.236`.

## Secrets

Calibre-Web users, passwords, and application-generated credentials live in the runtime config directory and must not be copied into Git. Provisioned bootstrap credentials belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md).

## Import Existing Library

For a fresh library import, populate the NAS `Books` shared folder over its
authenticated Samba share or the NFS export before starting Calibre-Web.
Preserve the complete Calibre directory structure and ensure `metadata.db` is
at the root of the share. The container must then see it at
`/books/metadata.db`.

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/calibre-web/config
sudo chown -R 1000:1000 /data/homelab/lab/calibre-web/config
cd ~/homelab/services/calibre-web
sudo docker compose -f compose.yml up -d
```

After the first start creates `/data/homelab/lab/calibre-web/config/app.db`, set `/books` as the default Calibre library path if needed:

```bash
python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/data/homelab/lab/calibre-web/config/app.db')
con.execute("update settings set config_calibre_dir=? where id=1", ('/books',))
con.commit()
con.close()
PY
sudo docker compose -f compose.yml restart calibre-web
```

On first login, verify the Calibre library path is `/books`.
