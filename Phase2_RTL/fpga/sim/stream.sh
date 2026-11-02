#!/usr/bin/env bash
set -euo pipefail
for tool in python3 verilator; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool; load its environment first" >&2; exit 127; }
done
board=$(cd "$(dirname "$0")/.." && pwd)
lanes=${1:-4}
case "$lanes" in 4|8|16) ;; *) exit 2 ;; esac
result="$board/sim/results_streaming_${lanes}"
mkdir -p "$result"
bash "$board/firmware/build.sh" streaming
work=$(mktemp -d /tmp/pynq-streaming.XXXXXX)
python3 "$board/scripts/sources.py" "$work"
cp "$board/firmware/build_streaming/firmware.mem" "$work/firmware.mem"
cp "$board/sim/tb_streaming.sv" "$board/sim/verilator.vlt" "$work/"
cp "$board/../uvm_tb/tb/ref.sv" "$work/"
cd "$work"
if ! verilator --binary --timing --assert -Wno-fatal -j 2 -Ifpga/rtl --top-module tb_streaming -GSTREAM_LANES="$lanes" verilator.vlt -f sources.f ref.sv tb_streaming.sv > "$result/build.log" 2>&1; then
  tail -n 60 "$result/build.log"
  exit 1
fi
./obj_dir/Vtb_streaming | tee "$result/run.log"
