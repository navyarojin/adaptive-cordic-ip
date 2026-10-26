"""Benchmark both model layers on PYNQ; run python3 bench.py.

Use --autonomous for cached weights and on-chip chaining (requires new overlay).
Model upload is performed once before warmup and excluded from timed inference.
Headline timing and counter collection use separate passes. Inputs are the same
271 preprocessed Q7 test rows for hardware and NumPy, batched identically.
"""
import argparse
import json
import time
from pathlib import Path
import numpy as np
from run import infer, infer_model

def stats(values):
    a = np.asarray(values, dtype=np.float64)
    return dict(mean=float(a.mean()), median=float(np.median(a)),
                min=float(a.min()), p95=float(np.percentile(a, 95)))

def requantize(x):
    return np.clip(np.sign(x) * ((np.abs(x) + 64) // 128), -128, 127).astype(np.int32)

def reference(inputs, model):
    from client import activation_reference
    values = np.asarray(inputs, dtype=np.int64)
    layers = []
    for layer, mode in ((1, 0), (2, 1)):
        z = np.clip(values @ np.asarray(model['weights%d' % layer]).T +
                    model['bias%d' % layer], -262144, 262143)
        values = np.array([[activation_reference(int(v), mode, 14) for v in row]
                           for row in z], dtype=np.int32)
        layers.append(values.copy())
        if layer == 1:
            values = requantize(values)
    return layers

def numpy_model(inputs, parameters):
    """Q7 model using mathematical tanh/sigmoid, not RTL-exact CORDIC."""
    w1, b1, w2, b2 = parameters
    output = []
    for start in range(0, len(inputs), 64):
        x = inputs[start:start + 64].astype(np.float64) / 128
        h = np.tanh(x @ w1.T + b1)
        h = np.clip(np.sign(h) * np.floor(np.abs(h) * 128 + .5), -128, 127) / 128
        p = 1 / (1 + np.exp(-(h @ w2 + b2)))
        output.extend(p.tolist())
    return np.asarray(output)

def diagnostic(npu, inputs, model, expected):
    """Measure stages; read completed counters before collect releases the bank."""
    stages = {}
    counters = []
    for start in range(0, len(inputs), 64):
        values = inputs[start:start + 64]
        for layer, mode in ((1, 'tanh'), (2, 'sigmoid')):
            t = time.perf_counter_ns()
            npu.submit(values, bank=0, tag=start * 2 + layer,
                       weights=model['weights%d' % layer], bias=model['bias%d' % layer],
                       right_shift=0, mode=mode, min_iter=14, max_iter=14,
                       full_iter=14, sample_rate=0)
            stages.setdefault('layer%d.submit_us' % layer, []).append((time.perf_counter_ns()-t)/1000)
            deadline = time.monotonic() + npu.timeout
            while not npu.stream.read(8) & (1 << 16):
                npu._check_firmware()
                if time.monotonic() >= deadline:
                    raise TimeoutError('Waiting for model layer completion')
                time.sleep(.0001)
            snapshot = npu.hardware_counters(0)
            if snapshot['input_vectors'] != len(values) or snapshot['output_vectors'] != len(values):
                raise AssertionError('Hardware vector counters disagree with batch size')
            counters.append(dict(layer=layer, start=start, vectors=len(values), **snapshot))
            t = time.perf_counter_ns()
            result = npu.collect(0, check=False)
            stages.setdefault('layer%d.collect_after_done_us' % layer, []).append((time.perf_counter_ns()-t)/1000)
            values = np.asarray(result['actual'], dtype=np.int32)
            np.testing.assert_array_equal(values, expected[layer-1][start:start+len(values)])
            if layer == 1:
                t = time.perf_counter_ns()
                values = requantize(values)
                stages.setdefault('interlayer.requantize_us', []).append((time.perf_counter_ns()-t)/1000)
    return stages, counters

def diagnostic_model(npu, inputs, model, expected):
    stages, counters = {}, []
    for start in range(0, len(inputs), 64):
        values = inputs[start:start+64]
        t = time.perf_counter_ns()
        npu.submit_model(values, bank=0, tag=start+1)
        stages.setdefault('model.submit_us', []).append((time.perf_counter_ns()-t)/1000)
        deadline = time.monotonic()+npu.timeout
        while not npu.stream.read(8) & (1<<16):
            npu._check_firmware()
            if time.monotonic() >= deadline:
                raise TimeoutError('Waiting for autonomous model')
            time.sleep(.0001)
        snapshot = npu.hardware_counters(0)
        if snapshot['input_vectors'] != len(values) or snapshot['output_vectors'] != len(values):
            raise AssertionError('Model counters disagree with batch size')
        counters.append(dict(layer=0, start=start, vectors=len(values), **snapshot))
        t = time.perf_counter_ns()
        result = npu.collect(0, check=False)
        stages.setdefault('model.collect_after_done_us', []).append((time.perf_counter_ns()-t)/1000)
        np.testing.assert_array_equal(result['actual'], expected[1][start:start+len(values), :1])
    return stages, counters

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--autonomous', action='store_true', help='Measure on-chip two-layer path')
    parser.add_argument('--runs', type=int, default=100)
    parser.add_argument('--profiles', type=int, default=5)
    parser.add_argument('--output', default=None)
    args = parser.parse_args()
    if args.runs < 1 or args.profiles < 1:
        parser.error('runs and profiles must be positive')
    if args.output is None:
        args.output = 'banknote_autonomous_results.json' if args.autonomous else 'banknote_benchmark_results.json'
    run_inference = infer_model if args.autonomous else infer
    folder = Path(__file__).resolve().parent
    model = json.loads((folder/'model.json').read_text())
    inputs = np.asarray(model['test_inputs'], dtype=np.int32)
    labels = np.asarray(model['test_labels'])
    expected = reference(inputs, model)
    parameters = (np.asarray(model['weights1'], dtype=np.float64)/128,
                  np.asarray(model['bias1'], dtype=np.float64)/16384,
                  np.asarray(model['weights2'][0], dtype=np.float64)/128,
                  model['bias2'][0]/16384)
    cpu_expected = numpy_model(inputs, parameters)
    np.testing.assert_allclose(cpu_expected, model['quantized_math_probabilities'], rtol=0, atol=1e-14)
    from pynq import Overlay
    from stream import StreamingNPU
    npu = StreamingNPU(Overlay(str(folder/'board.bit')))
    hardware_us, python_us, all_counters, all_stages = [], [], [], {}
    try:
        npu.wait_ready()
        if npu.lanes != 4 or npu.max_vectors != 64 or npu.stream.read(0x34) & 0xFFFF0003 != 0x10003:
            raise RuntimeError('Expected the matching four-lane fused overlay')
        npu.prepare_buffers()
        if args.autonomous:
            npu.load_model(model)
        for _ in range(3):
            np.testing.assert_array_equal(run_inference(npu, inputs, model, check=False), expected[1][:, 0])
            numpy_model(inputs, parameters)

        for repeat in range(args.runs):
            for kind in (('hardware', 'python') if repeat % 2 == 0 else ('python', 'hardware')):
                t = time.perf_counter_ns()
                actual = run_inference(npu, inputs, model, check=False) if kind == 'hardware' else numpy_model(inputs, parameters)
                elapsed = (time.perf_counter_ns()-t)/1000
                if kind == 'hardware':
                    hardware_us.append(elapsed)
                    np.testing.assert_array_equal(actual, expected[1][:, 0])
                else:
                    python_us.append(elapsed)
                    np.testing.assert_array_equal(actual, cpu_expected)
        for _ in range(args.profiles):
            stages, counters = (diagnostic_model if args.autonomous else diagnostic)(npu, inputs, model, expected)
            all_counters.extend(counters)
            for key, value in stages.items():
                all_stages.setdefault(key, []).extend(value)
    finally:
        npu.close()
    hw, cpu = stats(hardware_us), stats(python_us)
    report = dict(execution_mode='autonomous' if args.autonomous else 'host_chained', samples_per_run=len(inputs), batch_sizes=[64,64,64,64,15],
                  runs=args.runs, diagnostic_passes=args.profiles,
                  hardware_workflow_us=hw, numpy_model_us=cpu,
                  hardware_raw_us=hardware_us, numpy_raw_us=python_us,
                  diagnostic_stage_us={k:stats(v) for k,v in all_stages.items()},
                  hardware_counters=all_counters,
                  hardware_accuracy=float(np.mean((expected[1][:,0]>=8192)==labels)),
                  numpy_accuracy=float(np.mean((cpu_expected>=.5)==labels)),
                  clock_mhz=25,
                  scope='Preprocessed Q7 inputs to model probabilities; excludes raw-feature normalization, allocation and reference checks. Hardware includes both layers, interlayer conversion (on-chip in autonomous mode), DMA and mailbox; one-time model upload excluded. NumPy uses mathematical activations and preprepared parameters. Counters are a separate diagnostic pass.')
    Path(args.output).write_text(json.dumps(report, indent=2)+'\n')
    for name, values in (('Full FPGA workflow', hw), ('NumPy mathematical model', cpu)):
        print('%s: median=%.2f us, min=%.2f us, p95=%.2f us per %d examples' %
              (name, values['median'], values['min'], values['p95'], len(inputs)))
    print('FPGA effective throughput: %.0f classifications/second' % (len(inputs)*1e6/hw['median']))
    print('NumPy median / FPGA workflow median: %.4fx' % (cpu['median']/hw['median']))
    print('Correctness PASS: every measured run checked outside timing; ' + ('final model outputs' if args.autonomous else 'both layers') + ' checked in diagnostics.')
    print('Diagnostic stage medians per invocation (includes 64- and 15-row batches):')
    for name, values in sorted(all_stages.items()):
        print('  %s: %.2f' % (name, stats(values)['median']))
    for layer in ((0,) if args.autonomous else (1,2)):
        for count in (64,15):
            rows=[r for r in all_counters if r['layer']==layer and r['vectors']==count]
            first=stats([r['first_input_to_first_output'] for r in rows])['median']
            span=stats([r['first_input_to_last_output'] for r in rows])['median']
            print('Layer/model %d, %d vectors: first-output %.2f cycles (%.3f us); first-input to last-output %.2f cycles (%.3f us)' %
                  (layer,count,first,first/25,span,span/25))
    print(report['scope'])
    print('Diagnostic collect times exclude completion waits handled before counter reads; do not sum them as headline latency.')
    print('Saved:', args.output)

if __name__ == '__main__':
    main()
