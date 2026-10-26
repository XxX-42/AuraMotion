#!/usr/bin/env python3
"""Opt-in macOS process-only CPU/RSS sampling; never part of the cursor path."""
import argparse
import csv
import json
import statistics
import subprocess
import time
from pathlib import Path


def cpu_seconds(value):
    days = 0
    if "-" in value:
        prefix, value = value.split("-", 1)
        days = int(prefix)
    result = 0.0
    for component in value.split(":"):
        result = result * 60 + float(component)
    return days * 86400 + result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=15)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.seconds <= 0 or args.seconds > 300:
        parser.error("--seconds must be in (0, 300]")
    rows = []
    started = time.monotonic()
    while True:
        observed = time.monotonic()
        result = subprocess.run(
            ["ps", "-p", str(args.pid), "-o", "time=,rss="],
            text=True, capture_output=True, check=False,
        )
        if result.returncode or not result.stdout.strip():
            break
        cpu, rss = result.stdout.split()
        rows.append({"elapsed_s": observed - started, "cpu_seconds": cpu_seconds(cpu), "rss_mib": int(rss) / 1024})
        if observed - started >= args.seconds:
            break
        time.sleep(min(1, max(0, args.seconds - (time.monotonic() - started))))
    if len(rows) < 2:
        raise SystemExit("Process exited or insufficient observations; no metrics claimed")
    duration = rows[-1]["elapsed_s"] - rows[0]["elapsed_s"]
    summary = {
        "source": "live_process_ps", "pid": args.pid, "duration_s": duration,
        "cpu_percent_one_core_100": 100 * (rows[-1]["cpu_seconds"] - rows[0]["cpu_seconds"]) / duration,
        "rss_mib_median": statistics.median(row["rss_mib"] for row in rows),
        "rss_mib_max": max(row["rss_mib"] for row in rows), "sample_count": len(rows),
        "scope": "AuraMotion process only; excludes other system processes and camera-to-display latency",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.with_suffix(".json").write_text(json.dumps(summary, indent=2) + "\n")
    with args.output.with_suffix(".csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
