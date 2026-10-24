#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/asic/reports"
mkdir -p "$out"
work=$(mktemp -d /tmp/npu-asic-lint.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
while IFS= read -r source || [[ -n "$source" ]]; do
  source=${source%$'\r'}
  [[ -z "$source" ]] && continue
  mkdir -p "$work/$(dirname "$source")"
  cp "$root/$source" "$work/$source"
done < "$root/asic/verification.f"
cp "$root/asic/verification.f" "$work/sources.f"
cd "$work"
verilator --version > "$out/tool.log"
verilator --lint-only --top-module stream_mmio -GLANES=4 -Wall -Wno-fatal \
  -f sources.f > "$out/lint.log" 2>&1

if grep -q '^%Error' "$out/lint.log" || \
   grep '^%Warning-' "$out/lint.log" | grep -Ev '^%Warning-(PINCONNECTEMPTY|GENUNNAMED|UNUSEDSIGNAL|UNUSEDPARAM):' >/dev/null; then
  cat "$out/lint.log"
  echo 'FAIL: inspect RTL lint diagnostics'
  exit 1
fi
echo 'PASS RTL structural lint; review retained unused/declaration warnings separately'
