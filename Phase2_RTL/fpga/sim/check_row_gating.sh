#!/usr/bin/env bash
set -euo pipefail
board=$(cd "$(dirname "$0")/.." && pwd)
report="$board/reports/row_gating_20261029"
work=$(mktemp -d /tmp/npu-row.XXXXXX)
trap 'case "$work" in /tmp/npu-row.*) rm -rf -- "$work" ;; esac' EXIT
python3 "$board/scripts/sources.py" "$work"
cp "$board/firmware/build_streaming/firmware.mem" "$work/firmware.mem"
cp "$board/sim/tb_streaming.sv" "$board/sim/tb_reset_closure.sv" "$board/sim/tb_auto.sv" "$board/sim/verilator.vlt" "$work/"
cp "$board/../uvm_tb/tb/ref.sv" "$work/"
cp "$report/autonomous/"*.mem "$work/"
cd "$work"
for entry in tb_streaming:tb_streaming.sv tb_reset_closure:tb_reset_closure.sv tb_autonomous_model:tb_auto.sv; do
  top=${entry%%:*}
  source_file=${entry#*:}
  mkdir -p "$report/system/$top"
  if ! verilator --binary --timing --assert -Wno-fatal -j 1 -Ifpga/rtl --top-module "$top" --Mdir "obj_$top" verilator.vlt -f sources.f ref.sv "$source_file" > "$report/system/$top/build.log" 2>&1; then
    tail -n 50 "$report/system/$top/build.log"
    exit 1
  fi
  "./obj_$top/V$top" | tee "$report/system/$top/run.log"
done
