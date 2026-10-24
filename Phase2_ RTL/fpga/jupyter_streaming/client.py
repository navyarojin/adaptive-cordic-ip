import operator
import threading
import time

def _integer(value, low, high, name):
    if isinstance(value, bool):
        raise ValueError(name + " must be an integer")
    try:
        result = operator.index(value)
    except TypeError as exc:
        raise ValueError(name + " must be an integer") from exc
    if not low <= result <= high:
        raise ValueError("{} must be in [{}, {}]".format(name, low, high))
    return result

def _signed(value):
    return value - 0x100000000 if value & 0x80000000 else value

def _sat(value, bits):
    return max(-(1 << (bits - 1)), min((1 << (bits - 1)) - 1, value))

def _div(n, d):
    q = (abs(n) + abs(d) // 2) // abs(d)
    return -q if (n < 0) != (d < 0) else q

def activation_reference(value, mode, iterations=14):
    if mode == 2:
        return max(0, _sat(value, 16))
    if mode == 3:
        return _sat(value, 16)
    reduced = (value + 1) >> 1 if mode == 1 else value
    if abs(reduced) >= 85197:
        result = 16383 if reduced > 0 else -16384
    else:
        halvings = 0
        while abs(reduced) > 16384:
            reduced = (reduced + 1) >> 1
            halvings += 1
        x, y, z = 16384, 0, reduced
        shifts = (1, 2, 3, 4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 13, 14)
        angles = (0, 9000, 4185, 2059, 1025, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1)
        for shift in shifts[:iterations]:
            direction = 1 if z >= 0 else -1
            x, y, z = (
                _sat(x + direction * ((y + (1 << (shift - 1))) >> shift), 18),
                _sat(y + direction * ((x + (1 << (shift - 1))) >> shift), 18),
                _sat(z - direction * angles[shift], 18),
            )
        result = _div(y * 16384, x)
        for _ in range(halvings):
            result = _div(2 * result * 16384, 16384 + _div(result * result, 16384))
        result = _sat(result, 16)
    return _sat((16384 + result + 1) >> 1 if mode == 1 else result, 16)

class NPU:
    MODES = {"tanh": 0, "sigmoid": 1, "relu": 2, "linear": 3}

    def __init__(self, overlay=None, mmio=None, timeout=5.0):
        if mmio is None:
            from pynq import MMIO
            entries = {} if overlay is None else dict(getattr(overlay, "mem_dict", {}))
            if overlay is not None:
                entries.update(overlay.ip_dict)
            if "mailbox_ctrl" not in entries:
                raise ValueError("Load board.bit with its matching .hwh file")
            info = entries["mailbox_ctrl"]
            if info["addr_range"] < 4096:
                raise ValueError("Mailbox address range is too small")
            mmio = MMIO(info["phys_addr"], 4096)
        self.mmio = mmio
        self.timeout = timeout
        self._lock = threading.Lock()
        if self.mmio.read(0xF00) != 0x4E505531 or self.mmio.read(0xF04) != 1:
            raise RuntimeError("Wrong overlay or mailbox ABI")
        self.wait_ready()

    def status(self):
        return {
            "boot_status": self.mmio.read(0xF08),
            "boot_checks_or_error": self.mmio.read(0xF0C),
            "mailbox_state": self.mmio.read(0x104),
            "requested": self.mmio.read(0),
            "completed": self.mmio.read(0x100),
        }

    def _check_firmware(self):
        status = self.mmio.read(0xF08)
        if status >> 16 == 0xDEAD:
            raise RuntimeError("CV32E40P failure 0x{:08x}; reload the overlay".format(self.mmio.read(0xF0C)))
        return status

    def wait_ready(self):
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if self._check_firmware() == 0x600D600D and self.mmio.read(0x104) in (1, 3, 4):
                return self.status()
            time.sleep(0.001)
        raise TimeoutError("CV32E40P boot/service not ready; check the overlay and LEDs")

    def run(self, weights, inputs, mode="linear", shift=0, min_iter=14,
            max_iter=14, full_iter=14, threshold=0, sample_rate=1):
        if len(weights) != 4 or any(len(row) != 4 for row in weights) or len(inputs) != 4:
            raise ValueError("Supply a 4x4 weight matrix and four inputs")
        weights = [[_integer(v, -128, 127, "weight") for v in row] for row in weights]
        inputs = [_integer(v, -128, 127, "input") for v in inputs]
        if isinstance(mode, str):
            if mode not in self.MODES:
                raise ValueError("Unknown activation mode")
            mode = self.MODES[mode]
        mode = _integer(mode, 0, 3, "mode")
        shift = _integer(shift, 0, 31, "shift")
        min_iter = _integer(min_iter, 6, 16, "min_iter")
        max_iter = _integer(max_iter, min_iter, 16, "max_iter")
        full_iter = _integer(full_iter, max_iter, 16, "full_iter")
        threshold = _integer(threshold, 0, 65535, "threshold")
        sample_rate = _integer(sample_rate, 0, 255, "sample_rate")
        with self._lock:
            self.wait_ready()
            completed = self.mmio.read(0x100)
            if self.mmio.read(0) != completed:
                raise RuntimeError("A request is still outstanding; wait or reload the overlay")
            fields = ((4, 1), (8, mode), (12, shift), (16, min_iter),
                      (20, max_iter), (24, threshold), (28, sample_rate), (0x70, full_iter))
            for addr, value in fields:
                self.mmio.write(addr, value)
            for i, value in enumerate(v for row in weights for v in row):
                self.mmio.write(0x20 + 4*i, value & 0xFFFFFFFF)
            for i, value in enumerate(inputs):
                self.mmio.write(0x60 + 4*i, value & 0xFFFFFFFF)
            if self.mmio.read(0x70) != full_iter:
                raise RuntimeError("Mailbox configuration readback failed")
            sequence = (completed + 1) & 0xFFFFFFFF
            self.mmio.write(0, sequence)
            deadline = time.monotonic() + self.timeout
            while self.mmio.read(0x100) != sequence:
                self._check_firmware()
                if time.monotonic() >= deadline:
                    raise TimeoutError("NPU request did not complete; do not overwrite an outstanding request")
                time.sleep(0.001)
            error = self.mmio.read(0x108)
            if error or self.mmio.read(0x104) != 3:
                raise RuntimeError("Firmware rejected/failed request: {}".format(error))
            raw = [_signed(self.mmio.read(0x120 + 4*i)) for i in range(4)]
            actual = [_signed(self.mmio.read(0x130 + 4*i)) for i in range(4)]
            expected_raw = [sum(w*x for w, x in zip(row, inputs)) for row in weights]
            expected = [activation_reference(_sat(v >> shift, 19), mode, full_iter) for v in expected_raw]
            exact = mode >= 2 or min_iter == full_iter or (sample_rate == 1 and threshold == 0)
            rows = [{"lane": i, "raw_actual": raw[i], "raw_expected": expected_raw[i],
                     "actual": actual[i], "full_reference": expected[i],
                     "difference": actual[i] - expected[i],
                     "raw_match": raw[i] == expected_raw[i],
                     "activation_match": actual[i] == expected[i]} for i in range(4)]
            cpu_checks = self.mmio.read(0x140)
            passed = all(r["raw_match"] and r["activation_match"] for r in rows) and cpu_checks == 5 if exact else None
            return {"sequence": sequence, "rows": rows, "passed": passed,
                    "exact_comparison": exact, "cpu_checks_passed": cpu_checks,
                    "comparison_checks_passed": sum(r["raw_match"] for r in rows) + sum(r["activation_match"] for r in rows),
                    "job_cycles": self.mmio.read(0x144),
                    "samples_total": self.mmio.read(0x148),
                    "max_residual_total": self.mmio.read(0x14C),
                    "fallbacks_total": self.mmio.read(0x150)}
