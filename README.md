# CORDIC NPU

Fixed-point tanh/sigmoid activation hardware with adaptive iteration control, a systolic MAC, and FPGA integration.

- `Phase1_Bitmodel/`: Python model, CORDIC notebook, and test vectors.
- `Phase2_ RTL/rtl/`: accelerator RTL; `sources.f` lists the sources.
- `Phase2_ RTL/verification/`, `asic/`, `uvm_tb/`, `spi_tb/`: verification flows.
- `Phase2_ RTL/fpga/`: firmware, build scripts, simulations, and PYNQ notebooks.
- `Phase2_ RTL/evaluation/`: evaluation scripts, model/test data, and saved results.
- 
## Python

From the project root, to install NumPy and run the frozen banknote model:

```powershell
python -m pip install numpy
python "Phase1_Bitmodel/model.py" 3.6216 8.6661 -2.8073 -0.44699
```

## Verilog Simulation (in Cadence Xcelium)

```bash
xrun -version
bash "Phase2_ RTL/spi_tb/run.sh" xrun
bash "Phase2_ RTL/asic/uvm.sh" 1
```

The first script runs SPI/accelerator tests; the second runs the streaming UVM test with seed `1` and coverage. Logs are saved in `Phase2_ RTL/spi_tb/results/` and `Phase2_ RTL/asic/reports/xcelium_seed_1/`. Check for `PASS` and no errors.

To view waveform in SimVision:

```bash
cd "Phase2_ RTL"
xrun -sv -f rtl/sources.f uvm_tb/tb/ref.sv verification/tb_accel.sv \
  -top tb_accelerator -timescale 1ns/1ps -access +rwc -gui
```
