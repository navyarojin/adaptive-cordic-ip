import importlib.util
import json
from pathlib import Path
import sys
import unittest

board = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(board / "jupyter_streaming"))
from client import NPU, activation_reference

class Memory:
    def __init__(self):
        self.data = {0xF00: 0x4E505531, 0xF04: 1, 0xF08: 0x600D600D,
                     0xF0C: 204, 0x104: 1, 0x100: 0, 0: 0}
        self.writes = 0
        self.complete = True
        self.bad_result = False

    def read(self, address):
        return self.data.get(address, 0)

    def write(self, address, value):
        self.writes += 1
        self.data[address] = value
        if address == 0 and self.complete:
            signed = lambda v: v - (1 << 32) if v & (1 << 31) else v
            for row in range(4):
                raw = sum(signed(self.read(0x20 + 4*(row*4+c))) * signed(self.read(0x60 + 4*c)) for c in range(4))
                result = activation_reference(raw >> self.read(12), self.read(8), self.read(0x70))
                self.data[0x120 + 4*row] = raw & 0xFFFFFFFF
                self.data[0x130 + 4*row] = (result + int(self.bad_result)) & 0xFFFFFFFF
            self.data.update({0x100: value, 0x104: 3, 0x108: 0, 0x140: 5})

class Tests(unittest.TestCase):
    weights = [[2, -1, 3, 4], [1, 2, -2, 0], [-3, 1, 1, 2], [0, 4, -1, 3]]
    inputs = [5, 0, -2, 1]

    def test_signed_comparison_and_repeat(self):
        memory = Memory()
        npu = NPU(mmio=memory)
        for seq, mode in enumerate(NPU.MODES, 1):
            result = npu.run(self.weights, self.inputs, mode=mode)
            self.assertTrue(result["passed"])
            self.assertEqual(result["sequence"], seq)
            self.assertEqual(result["rows"][0]["raw_actual"], 8)

    def test_invalid_input_has_no_writes(self):
        memory = Memory()
        npu = NPU(mmio=memory)
        for kwargs in ({"shift": -1}, {"min_iter": 17}, {"mode": "bad"}, {"sample_rate": 256}):
            with self.assertRaises(ValueError):
                npu.run(self.weights, self.inputs, **kwargs)
        with self.assertRaises(ValueError):
            npu.run(self.weights, [128, 0, 0, 0])
        self.assertEqual(memory.writes, 0)

    def test_mismatch_is_reported(self):
        memory = Memory()
        memory.bad_result = True
        self.assertFalse(NPU(mmio=memory).run(self.weights, self.inputs)["passed"])

    def test_approximate_is_not_exact_pass(self):
        result = NPU(mmio=Memory()).run(self.weights, self.inputs, mode="tanh", min_iter=6, max_iter=10, sample_rate=8)
        self.assertIsNone(result["passed"])
        self.assertFalse(result["exact_comparison"])

    def test_timeout_and_no_request_overwrite(self):
        memory = Memory()
        memory.complete = False
        npu = NPU(mmio=memory, timeout=0.005)
        with self.assertRaises(TimeoutError):
            npu.run(self.weights, self.inputs)
        writes = memory.writes
        with self.assertRaises(RuntimeError):
            npu.run(self.weights, self.inputs)
        self.assertEqual(memory.writes, writes)

    def test_identity_and_firmware_failure(self):
        memory = Memory()
        memory.data[0xF04] = 0
        with self.assertRaises(RuntimeError):
            NPU(mmio=memory)
        memory.data[0xF04] = 1
        memory.data[0xF08] = 0xDEAD0001
        with self.assertRaises(RuntimeError):
            NPU(mmio=memory)

    def test_reference_consistency(self):
        spec = importlib.util.spec_from_file_location("golden", board / "scripts/gen_vectors.py")
        golden = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(golden)
        for mode in range(4):
            for iterations in (6, 10, 14, 16):
                for value in range(-100000, 100001, 997):
                    self.assertEqual(activation_reference(value, mode, iterations), golden.activation(value, mode, iterations))

    def test_notebook_cells(self):
        notebook = json.loads((board / "jupyter_streaming/npu.ipynb").read_text())
        for cell in notebook["cells"]:
            if cell["cell_type"] == "code":
                compile("".join(cell["source"]), "notebook", "exec")

if __name__ == "__main__":
    unittest.main()
