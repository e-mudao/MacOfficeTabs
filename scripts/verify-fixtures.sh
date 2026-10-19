#!/bin/bash
# LaunchServices preserves app authorization context; directly executing the binary may inherit its caller's TCC context.
set -euo pipefail
cd "$(dirname "$0")/.."
app_dir="$PWD/build/MacOfficeTabs.app"
mkdir -p "$PWD/docs/evidence"
report_prefix="$PWD/docs/evidence/switches-$(date +%Y%m%d-%H%M%S)-$$"
/usr/bin/open -n -a "$app_dir" --stdout "$report_prefix.json" --stderr "$report_prefix.stderr" \
    --args --exercise-fixtures "$PWD/docs/evidence/fixtures"
for attempt in {1..120}; do
    if [ -s "$report_prefix.json" ]; then
        if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$report_prefix.json" >/dev/null 2>&1; then
            python3 - "$report_prefix.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    report=json.load(file)
print(f"Report: {sys.argv[1]}")
print(f"Samples: {report['sampleCount']}; attempts: {len(report['attempts'])}; allConfirmed: {report['allConfirmed']}")
if not report['allConfirmed']:
    for attempt in report['attempts']:
        if not attempt['confirmed']:
            print(attempt.get('error', 'Unconfirmed focus'))
    sys.exit(5)
PY
            exit 0
        fi
    fi
    if [ -s "$report_prefix.stderr" ]; then
        cat "$report_prefix.stderr"
        exit 4
    fi
    sleep 0.5
done
echo "No complete report within 60 seconds: $report_prefix" >&2
exit 6
