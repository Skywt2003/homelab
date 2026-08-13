#!/usr/bin/env python3
"""Build atomic mosdns domain/IP sets from maintained public sources."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import shutil
import tempfile
import urllib.request


SOURCES = {
    "cn_accelerated": "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf",
    "cn_google": "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf",
    "apple": "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf",
    "proxy": "https://raw.githubusercontent.com/Loyalsoldier/cn-blocked-domain/release/domains.txt",
    "cn_ip": "https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/text/cn.txt",
}


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "homelab-mosdns-rule-builder/1"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def dnsmasq_domains(payload: bytes) -> set[str]:
    result: set[str] = set()
    for raw in payload.decode("utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.search(r"server=/([^/]+)/", line)
        if match:
            result.add(match.group(1).lower().rstrip("."))
    return result


def plain_domains(payload: bytes) -> set[str]:
    result: set[str] = set()
    for raw in payload.decode("utf-8").splitlines():
        line = raw.split("#", 1)[0].strip().lower().rstrip(".")
        if line:
            result.add(line)
    return result


def plain_networks(payload: bytes) -> set[str]:
    networks: set[str] = set()
    for raw in payload.decode("utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            networks.add(str(ipaddress.ip_network(line, strict=False)))
    return networks


def write_lines(path: pathlib.Path, values: set[str]) -> None:
    path.write_text("".join(f"{value}\n" for value in sorted(values)), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument(
        "--source-dir",
        type=pathlib.Path,
        help="read pre-downloaded files named after the source keys instead of downloading",
    )
    args = parser.parse_args()

    if args.source_dir:
        payloads = {name: (args.source_dir / name).read_bytes() for name in SOURCES}
    else:
        payloads = {name: download(url) for name, url in SOURCES.items()}
    cn_domains = set().union(
        dnsmasq_domains(payloads["cn_accelerated"]),
        dnsmasq_domains(payloads["cn_google"]),
        dnsmasq_domains(payloads["apple"]),
    )
    apple_domains = dnsmasq_domains(payloads["apple"])
    proxy_domains = plain_domains(payloads["proxy"])
    cn_networks = plain_networks(payloads["cn_ip"])

    args.output.parent.mkdir(parents=True, exist_ok=True)
    staging = pathlib.Path(tempfile.mkdtemp(prefix="mosdns-rules-", dir=args.output.parent))
    try:
        write_lines(staging / "cn_domain.list", cn_domains)
        write_lines(staging / "apple_domain.list", apple_domains)
        write_lines(staging / "proxy_domain.list", proxy_domains)
        write_lines(staging / "cn_ip.list", cn_networks)
        manifest = {
            "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "sources": {
                name: {
                    "url": SOURCES[name],
                    "sha256": hashlib.sha256(payload).hexdigest(),
                }
                for name, payload in payloads.items()
            },
            "counts": {
                "cn_domain": len(cn_domains),
                "apple_domain": len(apple_domains),
                "proxy_domain": len(proxy_domains),
                "cn_ip": len(cn_networks),
            },
        }
        (staging / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        # tempfile.mkdtemp creates mode 0700. The directory is mounted read-only
        # into the container, so make the snapshot traversable and its files
        # world-readable before the atomic rename.
        staging.chmod(0o755)
        for generated_file in staging.iterdir():
            generated_file.chmod(0o644)

        old = args.output.with_name(args.output.name + ".old")
        if old.exists():
            shutil.rmtree(old)
        if args.output.exists():
            os.replace(args.output, old)
        os.replace(staging, args.output)
        if old.exists():
            shutil.rmtree(old)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


if __name__ == "__main__":
    main()
