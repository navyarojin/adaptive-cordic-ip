#!/usr/bin/env bash
set -euo pipefail
for tool in python3 verilator; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool; load its environment first" >&2; exit 127; }
done
board=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$board/sim/results"
bash "$board/firmware/build.sh"
work=$(mktemp -d /tmp/pynq-npu.XXXXXX)
echo "Simulation workspace: $work"
python3 "$board/scripts/sources.py" "$work"
cp "$board/firmware/build/firmware.mem" "$work/firmware.mem"
cp "$board/sim/tb_soc.sv" "$work/"
cp "$board/sim/verilator.vlt" "$work/"
cd "$work"
if ! verilator --binary --timing --assert -Wno-fatal -Wno-BLKANDNBLK -j 2 \
  -Ifpga/rtl --top-module tb_pynq_soc \
  verilator.vlt -f sources.f tb_soc.sv > "$board/sim/results/build.log" 2>&1; then
  tail -n 80 "$board/sim/results/build.log"
  exit 1
fi
./obj_dir/Vtb_pynq_soc | tee "$board/sim/results/run.log"
