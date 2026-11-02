# Zero-operand isolation prototypes

These modules implement alternatives to `rtl/systolic_cfg.sv`. They use its
interface, signed arithmetic, accumulator behavior and completion schedule.
They are excluded from the production source list and deployed bitstream.

- `zero_hold.sv`: capture only nonzero activations and propagate an explicit
  zero flag. Forward the partial sum on a zero operation. Keep weights connected
  directly to the multiplier. This targets stationary weights.
- `zero_dual_hold.sv`: retain both multiplier operands on invalid or zero-product
  operations. Forward the partial sum instead of consuming the retained product.
  This also isolates changes in weights during skipped operations.
- `tb_isolation.sv`: compare both prototypes, the original force-zero scheme,
  plain ungated logic and an ungated data-retention control against independent
  signed integer arithmetic.

Both alternatives retain operand data across functional clears, while clearing
accumulators and flushing valid state. Reset initializes all state. Neither
alternative skips execution cycles or gates the clock through fabric logic.
Supported array dimensions are 4, 8 and 16.

The complete experiment, including counterexamples, area, timing, switching and
power-estimation limits, is recorded in
[the consolidated findings](../../../output/NPU_Consolidated_Findings.pdf).
Original experiment records are available in the PDF's embedded evidence ZIP.
