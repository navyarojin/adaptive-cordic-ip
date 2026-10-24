import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "jupyter_streaming"))
from stream import StreamingNPU

class DmaModel:
    def __init__(self, statuses):
        self.statuses = list(statuses)
        self.writes = []

    def read(self, offset):
        if offset != 4:
            raise AssertionError("Unexpected DMA register read")
        if len(self.statuses) > 1:
            return self.statuses.pop(0)
        return self.statuses[0]

    def write(self, offset, value):
        self.writes.append((offset, value))

class MailboxModel:
    def __init__(self):
        self.words = {0: 0, 0x100: 0, 0x104: 3, 0x108: 0, 0x144: 123}
        self.writes = []

    def read(self, offset):
        return self.words.get(offset, 0)

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.words[offset] = value
        if offset == 0:
            self.words[0x100] = value

class StreamingClientTests(unittest.TestCase):
    def client(self, statuses=(2, 0, 2)):
        client = StreamingNPU.__new__(StreamingNPU)
        client.timeout = 0.001
        client.dma = DmaModel(statuses)
        client.mmio = MailboxModel()
        client.wait_ready = lambda: None
        client._check_firmware = lambda: None
        return client

    def test_dma_programming(self):
        client = self.client()
        client._copy(0x100000, 0x40011000, 1024)
        self.assertEqual(client.dma.writes, [(4, 0x7000), (0x18, 0x100000), (0x20, 0x40011000), (0x28, 1024)])

    def test_dma_rejects_alignment_and_length(self):
        for source, destination, size in ((1, 4, 4), (4, 1, 4), (4, 4, 3), (4, 4, 0), (4, 4, 0x800000)):
            client = self.client()
            with self.assertRaises(ValueError):
                client._copy(source, destination, size)
            self.assertFalse(client.dma.writes)

    def test_dma_busy_error_and_timeout(self):
        for statuses in ((0,), (0x42,), (2, 0x40)):
            with self.assertRaises(RuntimeError):
                self.client(statuses)._copy(0x100000, 0x40011000, 16)
        with self.assertRaises(TimeoutError):
            self.client((2, 0))._copy(0x100000, 0x40011000, 16)

    def test_cpu_command_publishes_sequence_last(self):
        client = self.client()
        cycles = client._command(2, ((0x74, 1), (0x78, 64)))
        self.assertEqual(cycles, 123)
        self.assertEqual(client.mmio.writes, [(4, 2), (0x74, 1), (0x78, 64), (0, 1)])

    def test_cpu_pending_and_rejection(self):
        client = self.client()
        client.mmio.words[0] = 1
        with self.assertRaises(RuntimeError):
            client._command(2, ())
        self.assertFalse(client.mmio.writes)
        client = self.client()
        client.mmio.words[0x108] = 7
        with self.assertRaises(RuntimeError):
            client._command(2, ())

class BufferModel:
    next_address = 0x100000

    def __init__(self, shape, dtype):
        import numpy as np
        self.data = np.zeros(shape, dtype=dtype)
        self.physical_address = BufferModel.next_address
        BufferModel.next_address += 0x1000
        self.freed = False
        self.flushes = self.invalidates = 0

    def __setitem__(self, index, value):
        self.data[index] = value

    def __getitem__(self, index):
        return self.data[index]

    def flush(self):
        self.flushes += 1

    def invalidate(self):
        self.invalidates += 1

    def freebuffer(self):
        self.freed = True

class ReusableBufferTests(unittest.TestCase):
    def setUp(self):
        import numpy as np
        import threading
        import types
        from unittest.mock import patch
        self.allocated = []

        def allocate(shape, dtype):
            buffer = BufferModel(shape, dtype)
            self.allocated.append(buffer)
            return buffer

        self.patch = patch.dict(sys.modules, {"pynq": types.SimpleNamespace(allocate=allocate)})
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.client = c = StreamingNPU.__new__(StreamingNPU)
        c._lock = threading.Lock()
        c.jobs = {}
        c._buffers = {}
        c._retained_buffers = []
        c.max_vectors = 64
        c.lanes = 4
        c.timeout = 0.01
        c.stream_base = 0x40010000
        c.stream = MailboxModel()
        c.stream.words = {8: 0, 0x1C: 0}
        self.inputs = {}
        self.transfers = []
        self.corrupt = False
        self.commands = []

        def command(op, fields):
            fields = dict(fields)
            self.commands.append((op, fields))
            bank = fields[0x74]
            if op in (2, 5):
                c.stream.words[8] |= (1 << (8 + bank)) | (1 << (16 + bank))
                c.stream.words[0x1C] &= ~(0xFFFF << (16 * bank))
                c.stream.words[0x1C] |= fields[0x7C] << (16 * bank)
            else:
                self.assertEqual(op, 3)
                c.stream.words[8] &= ~((1 << (8 + bank)) | (1 << (16 + bank)))
            return 111

        def copy(source, destination, size):
            self.transfers.append((source, destination, size))
            rows = size // (4 * c.lanes)
            if destination >= c.stream_base:
                bank = (destination - c.stream_base) // 0x1000 - 1
                self.inputs[bank] = c._buffers['tx'].data[:rows].copy()
            else:
                bank = (source - c.stream_base - 0x3000) // 0x1000
                c._buffers['rx'].data[:rows] = self.inputs[bank]
                if self.corrupt:
                    c._buffers['rx'].data[0, 0] += 1

        c._command = command
        c._copy = copy

    def test_reuse_two_banks_variable_sizes_and_independent_results(self):
        import numpy as np
        c = self.client
        c.prepare_buffers()
        self.assertEqual(len(self.allocated), 2)
        a = [[1, 2, 3, 4], [5, 6, 7, 8]]
        b = [[9, 10, 11, 12]]
        c.submit(a, bank=0, tag=1)
        c.submit(b, bank=1, tag=2)
        first = c.collect(0)
        second = c.collect(1)
        self.assertTrue(first['passed'])
        self.assertTrue(second['passed'])
        np.testing.assert_array_equal(first['actual'], a)
        np.testing.assert_array_equal(second['actual'], b)
        c.submit(b, bank=0, tag=3)
        c.collect(0)
        np.testing.assert_array_equal(first['actual'], a)
        self.assertEqual(len(self.allocated), 2)
        self.assertEqual([t[2] for t in self.transfers], [32, 16, 32, 16, 16, 16])
        self.assertEqual(c._buffers['tx'].flushes, 3)
        self.assertEqual(c._buffers['rx'].invalidates, 3)
        self.assertFalse(any(b.freed for b in self.allocated))
        c.close()
        self.assertTrue(all(b.freed for b in self.allocated))
        c.close()

    def test_unchecked_collection_never_calls_reference(self):
        from unittest.mock import patch
        import numpy as np
        c = self.client
        values = [[1, 2, 3, 4]]
        c.submit(values)
        with patch('stream.activation_reference', side_effect=AssertionError('Reference in timed path')):
            result = c.collect(check=False)
        np.testing.assert_array_equal(result['actual'], values)
        self.assertFalse(result['checked'])
        for key in ('expected', 'difference', 'passed'):
            self.assertIsNone(result[key])
        self.assertFalse(c.jobs)
        self.assertEqual(c.stream.words[8], 0)

    def test_default_check_detects_incorrect_output(self):
        c = self.client
        c.submit([[1, 2, 3, 4]])
        self.corrupt = True
        result = c.collect()
        self.assertTrue(result['checked'])
        self.assertFalse(result['passed'])
        self.assertEqual(result['difference'][0, 0], 1)

    def test_timeout_does_not_free_or_reuse_dma_buffer(self):
        from unittest.mock import Mock
        c = self.client
        c.prepare_buffers()
        c._copy = Mock(side_effect=TimeoutError('DMA still active'))
        with self.assertRaises(TimeoutError):
            c.submit([[1, 2, 3, 4]])
        saved = c._buffers['tx'].data.copy()
        with self.assertRaises(RuntimeError):
            c.submit([[5, 6, 7, 8]])
        with self.assertRaises(RuntimeError):
            c.prepare_buffers()
        with self.assertRaises(RuntimeError):
            c.close()
        import numpy as np
        np.testing.assert_array_equal(c._buffers['tx'].data, saved)
        self.assertEqual(c._copy.call_count, 1)
        self.assertFalse(any(b.freed for b in self.allocated))

    def test_close_rejects_outstanding_job_and_duplicate_submit(self):
        c = self.client
        c.submit([[1, 2, 3, 4]])
        with self.assertRaises(RuntimeError):
            c.close()
        with self.assertRaises(RuntimeError):
            c.submit([[5, 6, 7, 8]])
        c.collect()
        c.close()
        self.assertTrue(all(b.freed for b in self.allocated))

    def test_notebook_keeps_reference_and_checks_outside_timer(self):
        import contextlib
        import io
        import json
        import numpy as np
        from unittest.mock import patch
        from client import activation_reference
        notebook = json.loads((Path(__file__).resolve().parents[1] /
                               'jupyter_streaming/stream.ipynb').read_text())
        code = next(''.join(c['source']) for c in notebook['cells']
                    if 'def run_timed_job' in ''.join(c['source']))
        ticks = []
        checks = []
        scope = {}
        real_check = np.testing.assert_array_equal

        def clock():
            ticks.append(len(ticks))
            return len(ticks) * 1000

        def reference(*args):
            self.assertEqual(len(ticks), 0, 'Reference ran after timing began')
            return activation_reference(*args)

        def check(*args):
            self.assertGreater(len(ticks), 0)
            self.assertEqual(len(ticks) % 3, 0, 'Correctness check inside timer')
            checks.append(1)
            return real_check(*args)

        test = self

        class Board:
            lanes = 4
            max_vectors = 64
            MODES = StreamingNPU.MODES
            prepared = False

            def prepare_buffers(self):
                test.assertFalse(ticks)
                self.prepared = True

            def submit(self, *args, **kwargs):
                test.assertTrue(self.prepared)
                return {'submit_cpu_cycles': 111}

            def collect(self, bank, check=True):
                test.assertFalse(check)
                return {'actual': scope['expected'].copy(), 'exact_comparison': True}

        scope['npu'] = Board()
        with patch('time.perf_counter_ns', side_effect=clock), \
             patch('client.activation_reference', side_effect=reference), \
             patch('numpy.testing.assert_array_equal', side_effect=check), \
             contextlib.redirect_stdout(io.StringIO()):
            exec(compile(code, 'benchmark notebook cell', 'exec'), scope)
        self.assertEqual(len(ticks), 105 * 3)
        self.assertEqual(len(checks), 105)
        self.assertEqual(len(scope['samples']), 100)

    def test_profile_stage_attribution_and_totals(self):
        from unittest.mock import patch
        c = self.client
        c.prepare_buffers()
        clock = [0]
        original_copy, original_command = c._copy, c._command

        def copy(*args):
            clock[0] += 7000
            return original_copy(*args)

        def command(*args):
            clock[0] += 11000
            return original_command(*args)

        c._copy, c._command = copy, command
        with patch('stream.time.perf_counter_ns', side_effect=lambda: clock[0]):
            submission = c.submit([[1, 2, 3, 4]], profile=True)
            result = c.collect(check=False, profile=True)
        a, b = submission['timings_us'], result['timings_us']
        self.assertEqual(a['input_dma'], 7)
        self.assertEqual(a['mailbox_command'], 11)
        self.assertEqual(b['output_dma'], 7)
        self.assertEqual(b['bank_release'], 11)
        self.assertNotIn('reference_calculation', b)
        for timings in (a, b):
            self.assertEqual(timings['total_us'], 18)
            self.assertEqual(timings['total_us'], sum(v for k, v in timings.items() if k != 'total_us'))
            self.assertTrue(all(v >= 0 for v in timings.values()))
        self.assertFalse(result['checked'])
        self.assertEqual(len(self.allocated), 2)

    def test_profiling_disabled_does_not_read_clock(self):
        from unittest.mock import patch
        c = self.client
        with patch('stream.time.perf_counter_ns', side_effect=AssertionError('Unexpected timer')):
            submission = c.submit([[1, 2, 3, 4]])
            result = c.collect()
        self.assertNotIn('timings_us', submission)
        self.assertNotIn('timings_us', result)
        self.assertTrue(result['passed'])

    def test_profiled_collection_can_still_check_reference(self):
        c = self.client
        c.submit([[1, 2, 3, 4]], profile=True)
        result = c.collect(profile=True)
        self.assertTrue(result['passed'])
        self.assertIn('reference_calculation', result['timings_us'])

    def test_profile_notebook_runs_with_reusable_buffers(self):
        import contextlib
        import io
        import json
        import numpy as np
        notebook = json.loads((Path(__file__).resolve().parents[1] /
                               'jupyter_streaming/stream.ipynb').read_text())
        code = next(''.join(c['source']) for c in notebook['cells']
                    if 'profile_samples = []' in ''.join(c['source']))
        scope = dict(npu=self.client, benchmark_values=[[1, 2, 3, 4]],
                     expected=np.array([[1, 2, 3, 4]]), mode='linear', iterations=14)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exec(compile(code, 'profile notebook cell', 'exec'), scope)
        self.assertEqual(len(scope['profile_samples']), 20)
        self.assertEqual(len(self.allocated), 2)
        self.assertIn('Correctness PASS: 20 profiled batches', output.getvalue())
        self.assertFalse(self.client.jobs)

    def test_numpy_input_validation_rejects_before_dma(self):
        import numpy as np
        invalid = [
            np.ones((1, 4), dtype=np.float64),
            np.ones((1, 4), dtype=bool),
            np.ones((1, 4), dtype=np.complex128),
            np.full((1, 4), 2**63, dtype=np.uint64),
            np.full((1, 4), -262145, dtype=np.int64),
            np.full((1, 4), 262144, dtype=np.int64),
            np.zeros((0, 4), dtype=np.int32),
            np.zeros((65, 4), dtype=np.int32),
            np.zeros((2, 3), dtype=np.int32),
            np.zeros(4, dtype=np.int32),
            [[True, 2, 3, 4]], [[1.0, 2, 3, 4]],
            [[1, 2], [3, 4, 5, 6]],
            np.array([[1, 2, 3.0, 4]], dtype=object),
        ]
        for values in invalid:
            with self.subTest(values=repr(values)):
                with self.assertRaises(ValueError):
                    self.client.submit(values)
        self.assertFalse(self.transfers)
        self.assertFalse(self.allocated)
        self.assertFalse(self.client.jobs)

    def test_array_normalization_preserves_values_and_boundaries(self):
        import numpy as np
        base = np.arange(32, dtype=np.int64).reshape(4, 8)
        for values in (base[:, ::2], base[:, 1::2][::-1],
                       np.array([[-262144, 262143, 0, -1]], dtype='>i4'),
                       np.array([[0, 1, 2, 262143]], dtype=np.uint64)):
            with self.subTest(dtype=values.dtype):
                result = self.client.prepare_values(values)
                self.assertEqual(result.dtype, np.dtype(np.int32))
                self.assertTrue(result.flags.c_contiguous)
                self.assertFalse(np.shares_memory(values, result))
                np.testing.assert_array_equal(result, values)

    def test_array_mutation_cannot_change_submitted_reference(self):
        import numpy as np
        values = np.array([[1, 2, 3, 4]], dtype=np.int32)
        self.client.submit(values)
        values[:] = 99
        result = self.client.collect()
        self.assertTrue(result['passed'])
        np.testing.assert_array_equal(result['actual'], [[1, 2, 3, 4]])

    def test_numpy_nonlinear_reference_uses_wide_python_integers(self):
        import numpy as np
        from client import activation_reference
        values = np.array([[65536, -65536, 85196, -85196]], dtype=np.int32)
        self.client.submit(values, mode='tanh')
        expected = np.array([[activation_reference(int(x), 0, 14) for x in values[0]]], dtype=np.int32)
        self.inputs[0] = expected.copy()
        result = self.client.collect()
        self.assertTrue(result['passed'])
        np.testing.assert_array_equal(result['expected'], expected)

    def test_bulk_copy_uses_same_dtype_and_bounded_view(self):
        import numpy as np
        from unittest.mock import patch
        real_copy = np.copyto
        with patch('numpy.copyto', wraps=real_copy) as copier:
            self.client.submit(np.array([[1, 2, 3, 4]], dtype=np.int64))
        copier.assert_called_once()
        args, kwargs = copier.call_args
        self.assertEqual(args[0].shape, (1, 4))
        self.assertEqual(args[1].dtype, np.dtype(np.int32))
        self.assertEqual(kwargs, {'casting': 'no'})
        self.assertEqual(self.transfers[0][2], 16)

    def test_fused_command_packing_snapshot_and_reference(self):
        import numpy as np
        from client import activation_reference
        c = self.client
        c.stream.words[0x34] = 0x10003
        for mode in range(4):
            weights = [[2 if r == col else 0 for col in range(4)] for r in range(4)]
            bias = [-1, 1, 2147483647, -2147483648]
            c.submit([[-128, 127, 0, 0]], weights=weights, bias=bias, right_shift=1, mode=mode, tag=mode)
            op, fields = self.commands[-1]
            self.assertEqual(op, 5)
            self.assertEqual(fields[12], 1)
            self.assertEqual([fields[0x90+4*r] for r in range(4)], [2, 512, 131072, 33554432])
            self.assertEqual([fields[0xA0+4*r] for r in range(4)], [0xFFFFFFFF, 1, 0x7FFFFFFF, 0x80000000])
            weights[0][0] = 99
            bias[0] = 123
            expected = np.array([[activation_reference(x, mode, 14) for x in [-129, 128, 262143, -262144]]], dtype=np.int32)
            self.inputs[0] = expected.copy()
            result = c.collect()
            self.assertTrue(result['passed'])
            np.testing.assert_array_equal(result['expected'], expected)
        c.submit([[1, 2, 3, 4]])
        self.assertEqual(self.commands[-1][0], 2)
        self.assertTrue(c.collect()['passed'])

    def test_fused_validation_precedes_dma(self):
        c = self.client
        c.stream.words[0x34] = 0x10003
        identity = [[int(r == col) for col in range(4)] for r in range(4)]
        for kwargs in (
            dict(weights=[[1]*4]*3), dict(weights=[[128]*4]*4),
            dict(weights=[[True]*4]*4), dict(weights=identity, bias=[0]*3),
            dict(weights=identity, bias=[1 << 31]*4),
            dict(weights=identity, right_shift=32), dict(bias=[0]*4), dict(right_shift=1)
        ):
            with self.assertRaises(ValueError):
                c.submit([[1, 2, 3, 4]], **kwargs)
        with self.assertRaises(ValueError):
            c.submit([[128, 0, 0, 0]], weights=identity)
        c.stream.words[0x34] = 0xBAD00004
        with self.assertRaises(RuntimeError):
            c.submit([[1, 2, 3, 4]], weights=identity)
        self.assertEqual(self.transfers, [])
        self.assertEqual(self.commands, [])

    def test_hardware_counter_capability_completion_and_tag(self):
        c = self.client
        with self.assertRaises(RuntimeError):
            c.hardware_counters()
        c.stream.words[0x34] = 0x10003
        with self.assertRaises(RuntimeError):
            c.hardware_counters()
        c.submit([[1, 2, 3, 4]], bank=1, tag=44)
        for index, value in enumerate([3, 97, 160, 64, 64, 7, 2]):
            c.stream.words[0xA0+index*4] = value
        result = c.hardware_counters(1)
        self.assertEqual(result, dict(submit_to_first_input=3, first_input_to_first_output=97,
            first_input_to_last_output=160, input_vectors=64, output_vectors=64,
            input_stall_cycles=7, reference_stall_cycles=2, tag=44))
        c.stream.words[0x1C] = 45 << 16
        with self.assertRaises(RuntimeError):
            c.hardware_counters(1)

    def test_rx_timeout_retains_buffer_and_job(self):
        from unittest.mock import Mock
        c = self.client
        c.submit([[1, 2, 3, 4]])
        c._copy = Mock(side_effect=TimeoutError('Receive still active'))
        with self.assertRaises(TimeoutError):
            c.collect(check=False)
        self.assertIn(0, c.jobs)
        self.assertEqual(len(c._retained_buffers), 1)
        with self.assertRaises(RuntimeError):
            c.collect(check=False)
        with self.assertRaises(RuntimeError):
            c.close()
        self.assertFalse(any(b.freed for b in self.allocated))

if __name__ == "__main__":
    unittest.main()
