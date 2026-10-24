import sys
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'jupyter_streaming'))
from stream import StreamingNPU
from client import activation_reference

class Buffer(np.ndarray):
    def __new__(cls, address):
        obj = np.zeros((64, 4), dtype=np.int32).view(cls)
        obj.physical_address = address
        return obj

    def flush(self): pass
    def invalidate(self): pass

class ModelClientTests(unittest.TestCase):
    def setUp(self):
        c = self.c = StreamingNPU.__new__(StreamingNPU)
        c._lock = threading.Lock()
        c._model = None
        c.jobs = {}
        c._retained_buffers = []
        c.lanes, c.max_vectors, c.timeout = 4, 64, 1
        c.stream_base = 0x40010000
        c._buffers = {'tx': Buffer(0x1000), 'rx': Buffer(0x2000)}
        self.regs = {0x34: 0x10007, 0x3c: 0, 8: 0, 0x1c: 0}
        c.stream = SimpleNamespace(read=lambda a: self.regs.get(a, 0))
        self.commands, self.transfers, self.saved = [], [], {}
        identity = (np.eye(4, dtype=int)*127).tolist()
        self.model = dict(weights1=identity, bias1=[0]*4, weights2=identity, bias2=[0]*4)

        def command(cmd, fields):
            self.commands.append((cmd, fields))
            f = dict(fields)
            if cmd == 6:
                self.regs[0x3c] = 1
            elif cmd == 7:
                bank = f[0x74]
                self.regs[8] |= (1 << (8+bank)) | (1 << (16+bank))
                mask = 0xffff << (16*bank)
                self.regs[0x1c] = (self.regs[0x1c] & ~mask) | (f[0x7c] << (16*bank))
            elif cmd == 3:
                bank = f[0x74]
                self.regs[8] &= ~((1 << (8+bank)) | (1 << (16+bank)))
            return 100
        c._command = command

        def transfer(src, dst, size):
            self.transfers.append((src, dst, size))
            if src == 0x1000:
                bank = (dst-c.stream_base)//0x1000-1
                self.saved[bank] = c._buffers['tx'][:size//16].copy()
            else:
                bank = (src-c.stream_base-0x5000)//0x1000
                values = self.saved[bank].astype(np.int64)
                for mode in (0, 1):
                    z = values @ np.asarray(self.model['weights%d' % (mode+1)]).T
                    values = np.array([[activation_reference(int(v), mode, 14) for v in row] for row in z])
                    if mode == 0:
                        values = np.clip(np.sign(values)*((np.abs(values)+64)//128), -128, 127)
                c._buffers['rx'].reshape(-1)[:size//4] = values[:, 0]
        c._copy = transfer

    def test_load_once_two_banks_compact_dma_and_exact_reference(self):
        self.c.load_model(self.model)
        for bank, count in ((0, 1), (1, 64)):
            self.c.submit_model(np.tile([-128, -1, 0, 127], (count, 1)), bank=bank, tag=bank+5)
        with self.assertRaises(RuntimeError): self.c.load_model(self.model)
        for bank, count in ((1, 64), (0, 1)):
            result = self.c.collect(bank)
            self.assertTrue(result['passed'])
            self.assertEqual(result['actual'].shape, (count, 1))
            self.assertEqual(self.transfers[-1], (self.c.stream_base+0x5000+bank*0x1000, 0x2000, count*4))
        self.assertEqual([cmd for cmd, _ in self.commands], [6, 7, 7, 3, 3])
        for cmd, fields in self.commands:
            if cmd == 7: self.assertEqual(len(fields), 3)

    def test_validation_and_missing_model_precede_dma(self):
        with self.assertRaises(RuntimeError): self.c.submit_model([[0]*4])
        self.regs[0x34] = 0x10003
        with self.assertRaises(RuntimeError): self.c.load_model(self.model)
        self.regs[0x34] = 0x10007
        self.c.load_model(self.model)
        for bad in ([[128,0,0,0]], [[0.5,0,0,0]], [[True,0,0,0]]):
            with self.assertRaises(ValueError): self.c.submit_model(bad)
        self.assertFalse(self.transfers)

    def test_failed_load_invalidates_cached_model(self):
        self.c.load_model(self.model)
        self.c._command = Mock(side_effect=RuntimeError('Rejected'))
        with self.assertRaises(RuntimeError): self.c.load_model(self.model)
        self.assertIsNone(self.c._model)

if __name__ == '__main__':
    unittest.main()
