# CORDIC NPU

Fixed-point tanh/sigmoid activation hardware with adaptive iteration control, a systolic MAC, and FPGA integration.

- `Phase1_Bitmodel/`: Python model, CORDIC notebook, and test vectors.
- `Phase2_RTL/rtl/`: accelerator RTL; `sources.f` lists the sources.
- `Phase2_RTL/verification/`, `asic/`, `uvm_tb/`, `spi_tb/`: verification flows.
- `Phase2_RTL/fpga/`: firmware, build scripts, simulations, and PYNQ notebooks.
- `Phase2_RTL/evaluation/`: evaluation scripts, model/test data, and saved results.

## System Architecture

![CORDIC NPU System Architecture](SystemArchitecture.png)

## Python

From the project root to install NumPy and run the frozen banknote model:

```powershell
python -m pip install numpy
python "Phase1_Bitmodel/model.py" 3.6216 8.6661 -2.8073 -0.44699
```
## Verilog Simulation (in Cadence tools)

```bash
cd Phase2_RTL
bash run.sh check
bash run.sh spi
bash run.sh uvm 1
bash run.sh wave
```

`check` validates Bash syntax and source paths without a simulator. `spi` runs SPI/accelerator tests. `uvm 1` runs the streaming UVM test with seed 1 and coverage. `wave` opens the accelerator in SimVision; press Run to simulate. For UVM waveforms, use `bash run.sh uvm 1 wave`.

From inside `Phase2_RTL/spi_tb`, use `bash run.sh xrun` or `bash run.sh wave 1 tb_accelerator`. From inside `Phase2_RTL/asic`, use `bash uvm.sh 1`. Each runner resolves paths from its own location. The folder name is `Phase2_RTL` (no spaces).

Logs: `Phase2_RTL/spi_tb/results/` and `Phase2_RTL/asic/reports/xcelium_seed_1/`. Batch runs require a `PASS` marker and no simulation errors. SimVision scratch/waveform locations are printed by the SPI runner; UVM waveforms stay beside its logs.

## ASIC flow run

```bash
bash run.sh asic list
bash run.sh asic check
export ASIC_CONFIG=/absolute/path/site.tcl
bash run.sh asic check syn
bash run.sh asic syn
```

| Steps | Stage commands | Tool |
| --- | --- | --- |
| 1-4 | `spec`, `rtl`, `sim`, `lint` | Specification/source inventory, Xcelium, JasperGold |
| 5-7 | `syn`, `lec`, `pregls` | Genus, Conformal, Xcelium |
| 8-12 | `floor`, `power`, `place`, `cts`, `route` | Innovus |
| 13-15 | `pex`, `sta`, `postgls` | Quantus through Innovus, Tempus, Xcelium |
| 16-17 | `drc`, `arc`, `lvs` | PDK-qualified Pegasus/PVS commands |
| 18-19 | `eco`, `final_lec` | Innovus, Conformal |

Command references: [Genus/Conformal handoff](https://community.cadence.com/cadence_technology_forums/f/logic-design/59112/conformal-cec-checking), [Quantus extraction setup](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/33561/qrc-extraction-issue), [SDF corner export](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/17972/write_sdf-in-mmmc-flow).
