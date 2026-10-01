# 01 — Timestep red loop

Status: resolved
Type: task

## Question

What is the tightest command that goes red on the Metal `TIMESTEP_EMBEDDING` failure, and what does it prove about the cause?

## Answer

### The red loop

```sh
./vendor/llama.cpp/build-static/bin/test-backend-ops -b MTL0 -o TIMESTEP_EMBEDDING
```

Red output:

```
[TIMESTEP_EMBEDDING] ERR = 0.002926276 > 0.000000100 sentinel mismatch: sent_2   TIMESTEP_EMBEDDING(type=f32,ne_a=[2,1,1,1],dim=320,max_period=10000)
FAIL
  0/1 tests passed
```

Properties: one command, seconds, red on every run, deterministic FAIL, agent-runnable, no model file needed. Op filter confirmed from `--help` (`-o <op|regex,..>`). Full `test-backend-ops` is not needed to see red; the unfiltered run is the *regression* gate, not the red loop.

### Two independent failures on one line

The harness prints these from two separate callbacks, and the sentinel branch returns early:

- `ERR = ... > ...` — `test-backend-ops.cpp:1530-1536`, numeric mismatch of the op output against the CPU backend, threshold 1e-7.
- `sentinel mismatch: sent_2` — `test-backend-ops.cpp:1491-1502`, `memcmp` of a sentinel's GPU bytes against CPU bytes.

Both fire. This is not one bug reported twice.

### FINDING: the precision theory is disproven, not merely unproven

The prior session assumed `0114-metal-timestep-embedding-precise.patch` had never been built. It had been.

```
misc.metal          mtime 2026-10-01 22:50:39   (contains 4x precise::)
test-backend-ops    mtime 2026-10-01 22:55:06   (5 min newer)
```

The Metal backend compiles kernels at runtime, and the run confirms it:

```
ggml_metal_library_compile_pipeline: compiling pipeline: base = 'kernel_timestep_embedding_f32'
ggml_metal_library_compile_pipeline: loaded kernel_timestep_embedding_f32
```

So the `precise::exp/log/cos/sin` variant is what actually executed, and it still fails at 2.9e-3. The patch's entire purpose was to fix this; it does not. Q4's deletion was correct, and number 0114 is now free of a proven-bad occupant.

### FINDING: the error is non-deterministic

Four consecutive runs of the same binary:

```
ERR = 0.002926276
ERR = 0.002815395
ERR = 0.001138978
ERR = 0.001034973
```

A ~3x spread. Deterministic fast-math error cannot drift like this: same inputs, same kernel, same binary. The variation points at memory that is read before being written, or written out of bounds — not at arithmetic accuracy. Combined with the sentinel mismatch, this is an out-of-bounds-write signature.

### What the minimisation proved

- OOB write: **supported** — sentinel bytes differ between backends and the magnitude drifts run to run.
- Precision: **disproven** — `precise::` compiled in, still fails, and the value drifts.
- Init garbage: **not excluded** — same signature, needs discriminating instrumentation.

The remaining ambiguity between OOB and uninitialised read is resolved by the byte-level question: is `sent_2` non-zero garbage (something wrote there) or is the *output* tensor reading uninitialised memory? That is the next measurement, and it needs instrumentation in the Metal backend rather than more theory.

## Comments

- 2026-10-01: resolved. Red loop found and stable. `precise::` theory disproven by an actual build. Patch 0114 deleted (Q4) and its number reserved.
