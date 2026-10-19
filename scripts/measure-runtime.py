#!/usr/bin/env python3
"""Read-only process CPU/RSS sampling; does not control Office or read documents."""
import argparse
import datetime
import json
import subprocess
import time


def cpu_seconds(value):
    parts = value.split(":")
    return sum(float(part) * 60 ** index for index, part in enumerate(reversed(parts)))


parser = argparse.ArgumentParser()
parser.add_argument("--pid", type=int, required=True)
parser.add_argument("--samples", type=int, default=31)
parser.add_argument("--interval", type=float, default=2)
parser.add_argument("--label", required=True)
args = parser.parse_args()
if args.pid <= 0 or args.samples < 2 or args.interval <= 0:
    parser.error("positive PID/interval and at least two samples required")
records = []
started = time.monotonic()
for index in range(args.samples):
    output = subprocess.check_output(
        ["/bin/ps", "-p", str(args.pid), "-o", "time=,rss="], text=True
    ).strip().split()
    if len(output) != 2:
        raise SystemExit("Target process exited or accounting was unavailable")
    records.append({"elapsedSeconds": time.monotonic() - started,
                    "cpuSeconds": cpu_seconds(output[0]), "rssKiB": int(output[1])})
    if index + 1 < args.samples:
        time.sleep(args.interval)
elapsed = records[-1]["elapsedSeconds"] - records[0]["elapsedSeconds"]
cpu_delta = records[-1]["cpuSeconds"] - records[0]["cpuSeconds"]
if cpu_delta < 0 or elapsed <= 0:
    raise SystemExit("Invalid process accounting interval")
print(json.dumps({"timestampUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  "pid": args.pid, "label": args.label,
                  "method": "ps cumulative CPU delta / monotonic elapsed; RSS snapshots",
                  "cpuPercentOfOneCore": 100 * cpu_delta / elapsed,
                  "rssMiBMin": min(r["rssKiB"] for r in records) / 1024,
                  "rssMiBMax": max(r["rssKiB"] for r in records) / 1024,
                  "elapsedSeconds": elapsed, "samples": records}, indent=2))
