#!/usr/bin/env bash
set -euo pipefail
comparison=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$comparison/../.." && pwd)
work=$(mktemp -d /tmp/npu-published.XXXXXX)
cp "$comparison/published_baseline/"*.sv "$comparison/published_baseline/"*.v "$comparison/published_baseline/"*.vh "$work/"
cp "$root/rtl/div_stream.sv" "$root/rtl/act_stream.sv" "$work/"
cd "$work"
verilator --binary --timing --assert -Wno-fatal -j 2 --top-module tb_published_comparison -I. div_stream.sv act_stream.sv wrap.sv tb.sv > "$comparison/published_build.log" 2>&1
obj_dir/Vtb_published_comparison
python3 - "$comparison/metrics.json" <<'PY'
import csv
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
metrics = json.loads(path.read_text()) if path.exists() else {}
with open("published_accuracy.csv", newline="") as source:
    metrics["published_accuracy"] = list(csv.DictReader(source))
path.write_text(json.dumps(metrics, indent=2) + "\n")
PY
