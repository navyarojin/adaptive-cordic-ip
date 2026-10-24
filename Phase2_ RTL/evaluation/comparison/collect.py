import json
import re
from pathlib import Path

comparison = Path(__file__).resolve().parent
root = comparison.parent.parent
board = root / "fpga"

def number(text, label):
    match = re.search(r"\|\s*" + re.escape(label) + r"\s*\|\s*([0-9.,]+)", text)
    if match is None:
        raise ValueError("Missing report field: " + label)
    return float(match.group(1).replace(",", ""))

def timing(text):
    match = re.search(r"WNS\(ns\).*?\n\s*-+.*?\n\s*([-0-9.]+)\s+([-0-9.]+)\s+(\d+)\s+(\d+)\s+([-0-9.]+)", text, re.S)
    if match is None:
        raise ValueError("Missing timing summary")
    return float(match.group(1)), float(match.group(5))

def save(name, rows):
    if not rows:
        raise ValueError("No measurements for " + name)
    path = comparison / "metrics.json"
    metrics = json.loads(path.read_text()) if path.exists() else {}
    metrics[Path(name).stem] = [{key: str(value) for key, value in row.items()} for row in rows]
    path.write_text(json.dumps(metrics, indent=2) + "\n")

rows = []
for design in ("published_sigmoid_benchmark", "cordic_sigmoid_benchmark"):
    reports = board / "reports" / "published_verify"
    prefix = "published" if design.startswith("published") else "cordic"
    utilization = (reports / (prefix + "_area.rpt")).read_text()
    power = (reports / (prefix + "_power.rpt")).read_text()
    setup, hold = timing((reports / (prefix + "_time.rpt")).read_text())
    rows.append(dict(design=design, device="xc7z020clg400-1", clock_mhz=25,
        lut=int(number(utilization, "Slice LUTs")), ff=int(number(utilization, "Slice Registers")),
        dsp=int(number(utilization, "DSPs")), bram36_equivalent=number(utilization, "Block RAM Tile"),
        setup_slack_ns=setup, hold_slack_ns=hold,
        estimated_dynamic_w=number(power, "Dynamic (W)"), estimated_static_w=number(power, "Device Static (W)"),
        power_method="Vivado vectorless estimate; not board measurement",
        precision="Q4.12 interface; CORDIC uses Q14 internally",
        scope="one registered activation kernel; excludes CV32 and data movement"))
save("published_resources.csv", rows)

rows = []
for directory, lanes in (("build_streaming_axi", 1), ("build_streaming_parallel", 4)):
    reports = board / "reports" / directory
    paths = [reports / name for name in ("area.rpt", "power.rpt", "time.rpt")]
    if not all(path.exists() for path in paths):
        continue
    utilization, power, timing_text = [path.read_text() for path in paths]
    setup, hold = timing(timing_text)
    rows.append(dict(configuration=directory, streaming_lanes=lanes,
        device="xc7z020clg400-1", clock_mhz=25,
        lut=int(number(utilization, "Slice LUTs")), ff=int(number(utilization, "Slice Registers")),
        dsp=int(number(utilization, "DSPs")), bram36_equivalent=number(utilization, "Block RAM Tile"),
        setup_slack_ns=setup, hold_slack_ns=hold,
        estimated_dynamic_w=number(power, "Dynamic (W)"),
        estimated_static_w=number(power, "Device Static (W)"),
        estimated_ps7_w=number(power, "PS7"),
        power_method="Vivado vectorless estimate; includes Zynq PS; not board measurement",
        scope="CV32 plus legacy NPU SPI mailbox streaming activation buffers and AXI DMA"))
if rows:
    save("full_system_resources.csv", rows)

throughput = root / "spi_tb/results/tb_stream_throughput_lanes4.run.log"
if throughput.exists():
    rows = []
    for line in throughput.read_text().splitlines():
        if not line.startswith("STREAM_THROUGHPUT,"):
            continue
        lanes, rate, vectors, latency, sustained, total = map(int, line.split(",")[1:])
        if sustained <= 0 or total <= 0:
            raise ValueError("Invalid throughput measurement")
        rows.append(dict(lanes=lanes, sample_interval=rate or 256, vectors=vectors,
            first_result_latency_clocks=latency, sustained_window_clocks=sustained,
            complete_window_clocks=total, clock_mhz=25,
            sustained_activations_per_clock=lanes * vectors / sustained,
            sustained_mactivations_per_second=25 * lanes * vectors / sustained,
            scope="shared-reference activation array; excludes CPU and DMA"))
    save("stream_throughput.csv", rows)

rows = []
for stream_lanes in (4, 8, 16):
    firmware = board / f"sim/results_streaming_{stream_lanes}/run.log"
    if not firmware.exists():
        continue
    for line in firmware.read_text().splitlines():
        if line.startswith("HOST_BENCH,"):
            lanes, mode, cycles = map(int, line.split(",")[1:])
            rows.append(dict(path="legacy SPI complete job", mode=mode, lanes=lanes,
                             cycles=cycles, clock_mhz=25, microseconds=cycles / 25))
        elif line.startswith("STREAM_HOST_BENCH,"):
            mode, cycles = map(int, line.split(",")[1:])
            rows.append(dict(path="stream queue submission only", mode=mode, lanes=stream_lanes,
                             cycles=cycles, clock_mhz=25, microseconds=cycles / 25))
        elif line.startswith("STREAM_E2E_BENCH,"):
            lanes, mode, done_cycles, readback_cycles = map(int, line.split(",")[1:])
            for label, cycles in (("CV32 request to observed completion; four vectors preloaded", done_cycles),
                                  ("CV32 request through direct-BRAM result readback; excludes DMA", readback_cycles)):
                rows.append(dict(path=label, mode=mode, lanes=lanes,
                                 cycles=cycles, clock_mhz=25, microseconds=cycles / 25))
if rows:
    save("stream_firmware_latency.csv", rows)
