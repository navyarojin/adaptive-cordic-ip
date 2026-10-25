import time

from client import NPU, _integer, activation_reference

class _StageTimer:
    """Disjoint host wall-clock intervals; includes instrumentation overhead."""
    def __init__(self):
        self.last = time.perf_counter_ns()
        self.stages = {}

    def mark(self, name):
        now = time.perf_counter_ns()
        self.stages[name] = (now - self.last) / 1000
        self.last = now

    def result(self):
        return dict(self.stages, total_us=sum(self.stages.values()))

class StreamingNPU(NPU):
    def __init__(self, overlay, timeout=5.0):
        super().__init__(overlay=overlay, timeout=timeout)
        from pynq import MMIO
        entries = dict(getattr(overlay, "mem_dict", {}))
        entries.update(overlay.ip_dict)
        for name in ("stream_ctrl", "stream_dma"):
            if name not in entries:
                raise ValueError("The streaming overlay and matching HWH are required")
        info = entries["stream_ctrl"]
        self.stream_base = info["phys_addr"]
        self.stream = MMIO(self.stream_base, info["addr_range"])
        info = entries["stream_dma"]
        self.dma = MMIO(info["phys_addr"], info["addr_range"])
        if self.stream.read(0) != 0x53545231:
            raise RuntimeError("Streaming identity mismatch")
        capabilities = self.stream.read(4)
        self.lanes = capabilities & 0xFFFF
        self.max_vectors = capabilities >> 16
        self.jobs = {}
        self._retained_buffers = []
        self._buffers = {}
        self._model = None

    def _buffer(self, direction):

        if self._retained_buffers:
            raise RuntimeError("DMA state is uncertain; reload the overlay and create a new client")
        if direction not in self._buffers:
            import numpy as np
            from pynq import allocate
            self._buffers[direction] = allocate(
                shape=(self.max_vectors, self.lanes), dtype=np.int32)
        return self._buffers[direction]

    def prepare_buffers(self):
        """Allocate reusable TX/RX buffers before starting a benchmark timer."""
        with self._lock:
            self._buffer("tx")
            self._buffer("rx")

    def close(self):
        """Free cached buffers only after jobs and DMA transfers have completed."""
        with self._lock:
            if self.jobs or self._retained_buffers:
                raise RuntimeError("Collect outstanding jobs first; after DMA failure reload the overlay")
            for buffer in self._buffers.values():
                buffer.freebuffer()
            self._buffers.clear()

    def _copy(self, source, destination, size):
        if (source | destination | size) & 3 or not 0 < size <= 0x7FFFFF:
            raise ValueError("DMA addresses and length must be aligned to four bytes")
        status = self.dma.read(4)
        if not status & 2 or status & 0x70:
            raise RuntimeError("DMA is busy or has an error: 0x{:08x}".format(status))
        self.dma.write(4, 0x7000)
        self.dma.write(0x18, source)
        self.dma.write(0x20, destination)
        self.dma.write(0x28, size)
        deadline = time.monotonic() + self.timeout
        while True:
            status = self.dma.read(4)
            if status & 0x70:
                raise RuntimeError("DMA transfer failed: 0x{:08x}".format(status))
            if status & 2:
                return
            if time.monotonic() >= deadline:
                raise TimeoutError("DMA remains active; reload the overlay before reusing retained buffers")
            time.sleep(0.0001)

    def _command(self, command, fields):
        self.wait_ready()
        completed = self.mmio.read(0x100)
        if self.mmio.read(0) != completed:
            raise RuntimeError("A mailbox request is still outstanding")
        self.mmio.write(4, command)
        for address, value in fields:
            self.mmio.write(address, value)
        sequence = (completed + 1) & 0xFFFFFFFF
        self.mmio.write(0, sequence)
        deadline = time.monotonic() + self.timeout
        while self.mmio.read(0x100) != sequence:
            self._check_firmware()
            if time.monotonic() >= deadline:
                raise TimeoutError("CPU did not acknowledge the streaming command")
            time.sleep(0.0001)
        error = self.mmio.read(0x108)
        if error or self.mmio.read(0x104) != 3:
            raise RuntimeError("CPU rejected streaming command: {}".format(error))
        return self.mmio.read(0x144)

    def prepare_values(self, values):
        """Return a validated, private C-contiguous int32 snapshot of input values.

        Integer NumPy arrays use vectorized validation. Python iterables retain
        strict per-item integer checks, including rejection of bool and floats.
        No narrowing conversion occurs until range checks have passed.
        """
        import numpy as np
        if isinstance(values, np.ndarray) and values.dtype.kind != "O":
            if values.ndim != 2 or not 1 <= values.shape[0] <= self.max_vectors or values.shape[1] != self.lanes:
                raise ValueError("Supply 1 through {} vectors of {} lanes".format(self.max_vectors, self.lanes))
            if values.dtype.kind not in "iu":
                raise ValueError("Activation inputs must be integers, not bool or floating point")
            if int(values.min()) < -262144 or int(values.max()) > 262143:
                raise ValueError("activation input must be in [-262144, 262143]")
            return np.array(values, dtype=np.int32, order="C", copy=True)
        rows = [[_integer(x, -262144, 262143, "activation input") for x in row] for row in values]
        if not 1 <= len(rows) <= self.max_vectors or any(len(row) != self.lanes for row in rows):
            raise ValueError("Supply 1 through {} vectors of {} lanes".format(self.max_vectors, self.lanes))
        return np.array(rows, dtype=np.int32, order="C")

    def submit(self, values, bank=0, mode="linear", tag=0, min_iter=14,
               max_iter=14, full_iter=14, threshold=0, sample_rate=1,
               qualification_count=8, violation_limit=3, update_interval=32,
               freeze=False, profile=False, weights=None, bias=None, right_shift=0):
        """Submit activation-only, or a fused layer when weights is supplied.

        Fused weights are (4 outputs, 4 inputs), signed INT8; bias is four
        signed INT32 product-unit values. right_shift rounds ties away from
        zero before signed 19-bit saturation and the existing activation.
        profile=True adds host-side timings_us, not hardware cycle counts.
        """
        timer = _StageTimer() if profile else None
        import numpy as np
        bank = _integer(bank, 0, 1, "bank")
        tag = _integer(tag, 0, 65535, "tag")
        if isinstance(mode, str):
            if mode not in self.MODES:
                raise ValueError("Unknown activation mode")
            mode = self.MODES[mode]
        mode = _integer(mode, 0, 3, "mode")
        min_iter = _integer(min_iter, 6, 16, "min_iter")
        max_iter = _integer(max_iter, min_iter, 16, "max_iter")
        full_iter = _integer(full_iter, max_iter, 16, "full_iter")
        threshold = _integer(threshold, 0, 65535, "threshold")
        sample_rate = _integer(sample_rate, 0, 255, "sample_rate")
        qualification_count = _integer(qualification_count, 0, 65535, "qualification_count")
        violation_limit = _integer(violation_limit, 0, 65535, "violation_limit")
        update_interval = _integer(update_interval, 0, 65535, "update_interval")
        rows = self.prepare_values(values)
        layer = None
        if weights is not None:
            if self.lanes != 4 or int(rows.min()) < -128 or int(rows.max()) > 127:
                raise ValueError("Fused layers require four signed INT8 inputs per vector")
            w = [[_integer(x, -128, 127, "weight") for x in row] for row in weights]
            if len(w) != 4 or any(len(row) != 4 for row in w):
                raise ValueError("Weights must have shape (4 outputs, 4 inputs)")
            b = [0] * 4 if bias is None else [_integer(x, -(1 << 31), (1 << 31)-1, "bias") for x in bias]
            if len(b) != 4:
                raise ValueError("Supply four bias values")
            shift = _integer(right_shift, 0, 31, "right_shift")
            layer = (w, b, shift)
        elif bias is not None or right_shift != 0:
            raise ValueError("Bias and scaling require fused layer weights")
        if timer: timer.mark("input_validation")
        with self._lock:
            if timer: timer.mark("lock_wait")
            if layer is not None and self.stream.read(0x34) & 0xFFFF0002 != 0x00010002:
                raise RuntimeError("Fused layers require the rebuilt RTL and command-5 firmware")
            if bank in self.jobs or self.stream.read(8) & (1 << (8 + bank)):
                raise RuntimeError("Bank is owned by an outstanding or unreleased job")
            if timer: timer.mark("bank_check")
            buffer = self._buffer("tx")
            if timer: timer.mark("buffer_lookup_or_allocation")
            self._retained_buffers.append(buffer)
            np.copyto(buffer[:len(rows)], rows, casting="no")
            if timer: timer.mark("input_copy")
            buffer.flush()
            if timer: timer.mark("cache_flush")
            self._copy(buffer.physical_address, self.stream_base + 0x1000 * (bank + 1), len(rows) * self.lanes * 4)
            if timer: timer.mark("input_dma")
            self._retained_buffers.pop()
            fields = ((8, mode), (16, min_iter), (20, max_iter),
                (24, threshold), (28, sample_rate), (0x70, full_iter), (0x74, bank),
                (0x78, len(rows)), (0x7C, tag), (0x80, qualification_count),
                (0x84, violation_limit), (0x88, update_interval), (0x8C, int(bool(freeze))))
            if layer is not None:
                w, b, shift = layer
                fields += ((12, shift),)
                fields += tuple((0x90+4*r, sum((w[r][c] & 255) << (8*c) for c in range(4))) for r in range(4))
                fields += tuple((0xA0+4*r, b[r] & 0xFFFFFFFF) for r in range(4))
            cycles = self._command(5 if layer is not None else 2, fields)
            if timer: timer.mark("mailbox_command")
            self.jobs[bank] = dict(values=rows, mode=mode, full_iter=full_iter, tag=tag,
                exact=mode >= 2 or min_iter == full_iter or (sample_rate == 1 and threshold == 0),
                submit_cpu_cycles=cycles, layer=layer)
            result = dict(bank=bank, tag=tag, vectors=len(rows), submit_cpu_cycles=cycles)
            if timer:
                timer.mark("bookkeeping")
                result["timings_us"] = timer.result()
            return result

    def load_model(self, model):
        """Load a fixed-14 Q7 4->4 tanh->1 sigmoid model once, before jobs."""
        layers = []
        fields = []
        for layer in (1, 2):
            w = [[_integer(v, -128, 127, "weight") for v in row]
                 for row in model["weights%d" % layer]]
            b = [_integer(v, -(1 << 31), (1 << 31)-1, "bias")
                 for v in model["bias%d" % layer]]
            if len(w) != 4 or any(len(row) != 4 for row in w) or len(b) != 4:
                raise ValueError("Model layers require 4x4 weights and four biases")
            layers.append((w, b))
            base = 0x90 + (layer-1)*32
            fields.extend((base+4*r, sum((w[r][c]&255) << (8*c) for c in range(4))) for r in range(4))
            fields.extend((base+16+4*r, b[r]&0xFFFFFFFF) for r in range(4))
        with self._lock:
            if self.stream.read(0x34) & 0xFFFF0004 != 0x00010004:
                raise RuntimeError("Autonomous model requires the new model-capable bitstream")
            if self.jobs or self.stream.read(8) & 0x300:
                raise RuntimeError("Release all banks before replacing model weights")
            self._model = None
            self._command(6, tuple(fields))
            self._model = layers

    def submit_model(self, values, bank=0, tag=0):
        """One command for both layers; collect returns shape (N, 1) Q14."""
        import numpy as np
        bank = _integer(bank, 0, 1, "bank")
        tag = _integer(tag, 0, 65535, "tag")
        rows = self.prepare_values(values)
        if self.lanes != 4 or int(rows.min()) < -128 or int(rows.max()) > 127:
            raise ValueError("Model inputs require four signed INT8 values")
        with self._lock:
            if self._model is None or not self.stream.read(0x3C) & 1:
                raise RuntimeError("Call load_model after loading the overlay")
            if bank in self.jobs or self.stream.read(8) & (1 << (8+bank)):
                raise RuntimeError("Bank is owned by an outstanding or unreleased job")
            buffer = self._buffer("tx")
            self._retained_buffers.append(buffer)
            np.copyto(buffer[:len(rows)], rows, casting="no")
            buffer.flush()
            self._copy(buffer.physical_address, self.stream_base+0x1000*(bank+1), len(rows)*16)
            self._retained_buffers.pop()
            cycles = self._command(7, ((0x74,bank),(0x78,len(rows)),(0x7C,tag)))
            self.jobs[bank] = dict(values=rows, mode=1, full_iter=14, tag=tag,
                                  exact=True, submit_cpu_cycles=cycles, layer=None,
                                  model=self._model)
            return dict(bank=bank, tag=tag, vectors=len(rows), submit_cpu_cycles=cycles)

    def collect(self, bank=0, check=True, profile=False):
        """Collect/release; check=False skips reference; profile=True adds timings_us."""
        timer = _StageTimer() if profile else None
        import numpy as np
        bank = _integer(bank, 0, 1, "bank")
        if timer: timer.mark("argument_setup")
        with self._lock:
            if timer: timer.mark("lock_wait")
            if bank not in self.jobs:
                raise ValueError("No submitted job is recorded for this bank")
            job = self.jobs[bank]
            if timer: timer.mark("job_lookup")
            deadline = time.monotonic() + self.timeout
            while not self.stream.read(8) & (1 << (16 + bank)):
                self._check_firmware()
                if time.monotonic() >= deadline:
                    raise TimeoutError("Streaming job has not completed")
                time.sleep(0.0001)
            if timer: timer.mark("completion_wait")
            tag = (self.stream.read(0x1C) >> (16 * bank)) & 0xFFFF
            if tag != job["tag"]:
                raise RuntimeError("Completed tag differs from submitted tag")
            if timer: timer.mark("tag_check")
            buffer = self._buffer("rx")
            if timer: timer.mark("buffer_lookup_or_allocation")
            self._retained_buffers.append(buffer)
            model_job = job.get("model")
            self._copy(self.stream_base + (0x5000 if model_job else 0x3000) + bank * 0x1000, buffer.physical_address, len(job["values"]) * (1 if model_job else self.lanes) * 4)
            if timer: timer.mark("output_dma")
            buffer.invalidate()
            if timer: timer.mark("cache_invalidate")
            actual = (np.array(buffer.reshape(-1)[:len(job["values"])], copy=True).reshape(-1, 1)
                      if model_job else np.array(buffer[:len(job["values"])], copy=True))
            if timer: timer.mark("result_copy")
            self._retained_buffers.pop()
            self._command(3, ((0x74, bank),))
            if timer: timer.mark("bank_release")
            del self.jobs[bank]
            expected = None
            if check:
                reference_values = job["values"]
                if job.get("layer") is not None:
                    w, b, shift = job["layer"]
                    reference_values = []
                    for row in job["values"]:
                        scaled = []
                        for r in range(4):
                            total = b[r] + sum(int(row[c]) * w[r][c] for c in range(4))
                            magnitude = abs(total)
                            rounded = magnitude if shift == 0 else (magnitude + (1 << (shift-1))) >> shift
                            scaled.append(max(-262144, min(262143, -rounded if total < 0 else rounded)))
                        reference_values.append(scaled)
                expected = np.array([[activation_reference(int(x), job["mode"], job["full_iter"])
                                      for x in row] for row in reference_values], dtype=np.int32)
                if model_job:
                    values = np.asarray(job["values"], dtype=np.int64)
                    for index, (w, b) in enumerate(model_job):
                        sums = np.clip(values @ np.asarray(w, dtype=np.int64).T + b, -262144, 262143)
                        values = np.array([[activation_reference(int(v), index, 14) for v in row]
                                           for row in sums], dtype=np.int64)
                        if index == 0:
                            values = np.clip(np.sign(values)*((np.abs(values)+64)//128), -128, 127)
                    expected = values[:, :1].astype(np.int32)
                if timer: timer.mark("reference_calculation")
            result = dict(actual=actual, expected=expected,
                        difference=actual - expected if check else None,
                        passed=bool(np.array_equal(actual, expected)) if check and job["exact"] else None,
                        checked=bool(check), exact_comparison=job["exact"], tag=tag,
                        submit_cpu_cycles=job["submit_cpu_cycles"])
            if timer:
                timer.mark("bookkeeping_and_comparison")
                result["timings_us"] = timer.result()
            return result

    def hardware_counters(self, bank=0):
        """Read completed-job cycle snapshots before collect/release; no host timing."""
        bank = _integer(bank, 0, 1, "bank")
        with self._lock:
            if (self.stream.read(0x34) >> 16) != 1:
                raise RuntimeError("Hardware counters require the rebuilt RTL")
            if not self.stream.read(8) & (1 << (16 + bank)):
                raise RuntimeError("The bank has no completed job")
            tag = (self.stream.read(0x1C) >> (16*bank)) & 0xFFFF
            if bank in self.jobs and tag != self.jobs[bank]["tag"]:
                raise RuntimeError("Completed tag differs from submitted tag")
            names = ("submit_to_first_input", "first_input_to_first_output",
                     "first_input_to_last_output", "input_vectors", "output_vectors",
                     "input_stall_cycles", "reference_stall_cycles")
            result = {name: self.stream.read(0x80+bank*0x20+4*i) for i, name in enumerate(names)}
            result["tag"] = tag
            return result
