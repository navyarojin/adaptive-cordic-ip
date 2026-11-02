#!/usr/bin/env bash
set -euo pipefail
board=$(cd "$(dirname "$0")/.." && pwd)
result="$board/reports/engineering_closure_20261028/reset"
mkdir -p "$result"
work=$(mktemp -d /tmp/npu-reset.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
python3 "$board/scripts/sources.py" "$work"
cp "$board/firmware/build_streaming/firmware.mem" "$work/firmware.mem"
cp "$board/sim/tb_reset_closure.sv" "$board/sim/verilator.vlt" "$work/"
cd "$work"
if ! verilator --binary --timing --assert -Wno-fatal -j 2 -Ifpga/rtl --top-module tb_reset_closure verilator.vlt -f sources.f tb_reset_closure.sv > "$result/build.log" 2>&1; then
  tail -n 60 "$result/build.log"
  exit 1
fi
./obj_dir/Vtb_reset_closure | tee "$result/run.log"
