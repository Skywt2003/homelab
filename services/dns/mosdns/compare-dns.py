#!/usr/bin/env python3
"""Compare production mosdns :53 and alternate AdGuard :5354."""

from __future__ import annotations

import argparse
import csv
import ipaddress
import json
import pathlib
import re
import statistics
import subprocess
import time


ADDRESS_RE = re.compile(r"(?:has address|has IPv6 address)\s+(\S+)$")


def load_cn_networks(path: pathlib.Path):
    return [ipaddress.ip_network(line.strip()) for line in path.read_text().splitlines() if line.strip()]


def query(server: str, port: int, name: str, qtype: str, tcp: bool) -> dict:
    cmd = ["host", "-W", "5", "-R", "1", "-p", str(port), "-t", qtype]
    if tcp:
        cmd.append("-T")
    cmd.extend([name, server])
    started = time.perf_counter()
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    elapsed_ms = (time.perf_counter() - started) * 1000
    answers = []
    for line in proc.stdout.splitlines():
        match = ADDRESS_RE.search(line)
        if match:
            answers.append(match.group(1))
        elif " mail is handled by " in line:
            answers.append(line.split(" mail is handled by ", 1)[1])
    status = "ok" if proc.returncode == 0 else "error"
    if "NXDOMAIN" in proc.stdout or "not found: 3(NXDOMAIN)" in proc.stdout:
        status = "nxdomain"
    return {
        "status": status,
        "elapsed_ms": round(elapsed_ms, 3),
        "answers": sorted(set(answers)),
        "raw": proc.stdout.strip(),
    }


def classify(answers: list[str], networks) -> str:
    addrs = []
    for value in answers:
        try:
            addrs.append(ipaddress.ip_address(value))
        except ValueError:
            pass
    if not addrs:
        return "n/a"
    flags = [any(addr in network for network in networks if addr.version == network.version) for addr in addrs]
    return "cn" if all(flags) else "mixed" if any(flags) else "non-cn"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="100.64.0.2")
    parser.add_argument("--adguard-port", type=int, default=5354)
    parser.add_argument("--mosdns-port", type=int, default=53)
    parser.add_argument("--cases", type=pathlib.Path, default=pathlib.Path(__file__).with_name("test-cases.tsv"))
    parser.add_argument("--cn-ip", type=pathlib.Path, required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    cases = []
    with args.cases.open() as handle:
        for row in csv.reader((line for line in handle if not line.startswith("#")), delimiter="\t"):
            if row:
                cases.append(dict(zip(("category", "name", "qtype", "note"), row)))
    networks = load_cn_networks(args.cn_ip)
    results = []
    for case in cases:
        record = {**case, "resolvers": {}}
        for label, port in (("adguard", args.adguard_port), ("mosdns", args.mosdns_port)):
            samples = [query(args.server, port, case["name"], case["qtype"], False) for _ in range(args.runs)]
            successful = [sample["elapsed_ms"] for sample in samples if sample["status"] in {"ok", "nxdomain"}]
            record["resolvers"][label] = {
                "status": samples[-1]["status"],
                "answers": samples[-1]["answers"],
                "answer_geo": classify(samples[-1]["answers"], networks),
                "latency_ms_p50": round(statistics.median(successful), 3) if successful else None,
                "latency_ms_max": round(max(successful), 3) if successful else None,
                "samples": samples,
            }
        # One TCP query per resolver proves DNS-over-TCP parity without doubling
        # the benchmark workload.
        record["tcp"] = {
            "adguard": query(args.server, args.adguard_port, case["name"], case["qtype"], True),
            "mosdns": query(args.server, args.mosdns_port, case["name"], case["qtype"], True),
        }
        results.append(record)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print("category\tname\ttype\tadguard_p50_ms\tmosdns_p50_ms\tadguard_geo\tmosdns_geo\tanswers_equal")
    for record in results:
        a = record["resolvers"]["adguard"]
        m = record["resolvers"]["mosdns"]
        print(
            record["category"], record["name"], record["qtype"],
            a["latency_ms_p50"], m["latency_ms_p50"], a["answer_geo"], m["answer_geo"],
            a["answers"] == m["answers"], sep="\t"
        )


if __name__ == "__main__":
    main()
