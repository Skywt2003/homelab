# Calibre-Web

This stack runs Calibre-Web for `books.lab.skywt`.

The Web UI is exposed through the shared Caddy reverse proxy by labels in `compose.yml`.

Calibre-Web uses the existing Calibre library imported from `~/calibre.zip` as its default book library. The archive is extracted to the persistent books directory, with the Calibre `metadata.db` expected at `/books/metadata.db` inside the container. The runtime Calibre-Web app database should have `config_calibre_dir` set to `/books`.

Runtime state is stored outside this Git repository:

- `/data/homelab/lab/calibre-web/config`
- `/data/homelab/lab/calibre-web/books`

## Secrets

Calibre-Web users, passwords, and application-generated credentials live in the runtime config directory and must not be copied into Git. Provisioned bootstrap credentials belong in Infisical and follow the [Secret Management SOP](../../docs/secret-management-sop.md).

## Import Existing Library

The existing library archive is expected at `~/calibre.zip` on the lab host. Import it before the first start:

```bash
sudo mkdir -p /data/homelab/lab/calibre-web/{config,books}
sudo chown -R 1000:1000 /data/homelab/lab/calibre-web
python3 - <<'PY'
import os
import shutil
import zipfile
from pathlib import Path

src = Path.home() / "calibre.zip"
dst = Path("/data/homelab/lab/calibre-web/books")
with zipfile.ZipFile(src) as zf:
    for info in zf.infolist():
        name = info.filename
        if name.startswith("__MACOSX/") or "/__MACOSX/" in name:
            continue
        if name.endswith(".DS_Store") or "/.DS_Store" in name:
            continue
        parts = Path(name).parts
        if parts and parts[0] == "Calibre Library":
            rel = Path(*parts[1:])
        else:
            rel = Path(*parts)
        if not rel.parts:
            continue
        target = dst / rel
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as source, target.open("wb") as output:
            shutil.copyfileobj(source, output, length=1024 * 1024)
PY
sudo chown -R 1000:1000 /data/homelab/lab/calibre-web
```

## Deploy

```bash
sudo mkdir -p /data/homelab/lab/calibre-web/{config,books}
sudo chown -R 1000:1000 /data/homelab/lab/calibre-web
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
