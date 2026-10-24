"""Run the frozen Banknote model on the matching fused PYNQ overlay.

On the board: python3 run.py --autonomous
Omit --autonomous to check the original host-chained path.
Checks both layers against the fixed-14 CORDIC reference on all 271 test rows.
The test inputs are already normalized and quantized; do not preprocess again.
"""
import json
from pathlib import Path
import numpy as np

def infer(npu, inputs, model, check=True):
    """Return Q14 probabilities; retain host Q14-to-Q7 interlayer rounding."""
    inputs = np.asarray(inputs, dtype=np.int32)
    if inputs.ndim != 2 or inputs.shape[1] != 4:
        raise ValueError('Expected an (N, 4) array of Q7 integer inputs')
    outputs = []
    for start in range(0, len(inputs), 64):
        values = inputs[start:start + 64]
        for layer, mode in ((1, 'tanh'), (2, 'sigmoid')):
            npu.submit(values, bank=0, tag=(start * 2 + layer) & 65535,
                       weights=model['weights' + str(layer)],
                       bias=model['bias' + str(layer)], right_shift=0,
                       mode=mode, min_iter=14, max_iter=14, full_iter=14,
                       sample_rate=0)
            result = npu.collect(0, check=check)
            if check and result['passed'] is not True:
                raise AssertionError('Layer %d failed at row %d' % (layer, start))
            values = np.asarray(result['actual'], dtype=np.int32)
            if layer == 1:
                values = np.clip(np.sign(values) * ((np.abs(values) + 64) // 128),
                                 -128, 127).astype(np.int32)
        outputs.extend(values[:, 0].tolist())
    return np.asarray(outputs, dtype=np.int32)

def infer_model(npu, inputs, model=None, check=True):
    """Cached-model path: one input upload and final-output collection per batch."""
    inputs = np.asarray(inputs, dtype=np.int32)
    if inputs.ndim != 2 or inputs.shape[1] != 4:
        raise ValueError('Expected (N, 4) Q7 inputs')
    output = []
    for start in range(0, len(inputs), 64):
        npu.submit_model(inputs[start:start+64], bank=0, tag=(start+1)&65535)
        result = npu.collect(0, check=check)
        if check and result['passed'] is not True:
            raise AssertionError('Autonomous model result mismatch at row %d' % start)
        output.extend(result['actual'][:, 0].tolist())
    return np.asarray(output, dtype=np.int32)

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--autonomous', action='store_true', help='Use cached weights and on-chip layer chaining')
    args = parser.parse_args()
    from pynq import Overlay
    from stream import StreamingNPU
    folder = Path(__file__).resolve().parent
    model = json.loads((folder / 'model.json').read_text())
    npu = StreamingNPU(Overlay(str(folder / 'board.bit')))
    try:
        npu.wait_ready()
        capability = npu.stream.read(0x34)
        if capability >> 16 != 1 or not capability & 2:
            raise RuntimeError('Load the matching fused bitstream and HWH')
        npu.prepare_buffers()
        if args.autonomous:
            npu.load_model(model)
        probability_q14 = (infer_model if args.autonomous else infer)(npu, model['test_inputs'], model)
        labels = np.asarray(model['test_labels'])
        correct = int(np.count_nonzero((probability_q14 >= 8192) == labels))
        print(('Autonomous final outputs' if args.autonomous else 'Both layers') + ' match the fixed-14 reference on all %d examples' % len(labels))
        print('Accuracy: %d/%d (%.4f%%)' % (correct, len(labels), 100 * correct / len(labels)))
        if correct != 266 or len(labels) != 271:
            raise AssertionError('Accuracy differs from the evaluated frozen model')
    finally:
        npu.close()

if __name__ == '__main__':
    main()
