# Our own flash-attention kernel fails to create a pipeline, and tensor split requires it

## The defect

Every run of this branch's engine, at every size and both split modes, prints:

```
E ggml_metal_library_compile_pipeline: failed to create pipeline state:
  base = 'kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64'
E ggml_metal_library_compile_pipeline: Error Domain=CompilerError Code=2 "
  Linking two modules of different data layouts: '' is ''
  whereas '1' is 'e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-...
```

The kernel's module carries an **empty data layout** and is being linked against one that has a
full x86_64/apple layout. The pipeline never exists, so the kernel is silently unavailable every
time the engine runs.

The kernel is ours: `patches/shared-metal/0001-6-metal-flash-attn-amd.patch` and
`patches/llama/metal/0001-amd-backend-host.patch`, defined in
`vendor/llama.cpp/ggml/src/ggml-metal/kernels/fa.metal`. It is not present in upstream at the pin.

## Scope, measured

| condition | failed-pipeline lines |
|---|---|
| ours@AVX1, 0.6B, `-sm tensor` | 1 |
| ours@AVX1, 0.6B, `-sm layer` | 1 |
| ours@AVX1, 14B, `-sm tensor` | 1 |
| ours@AVX1, 14B, `-sm layer` | 1 |
| ours@SSE2, 0.6B, `-sm tensor` | 1 |
| ours@AVX1 with `bin/kernels/` removed (runtime compile) | **1** |
| shipped 0.87.26 baseline | **0** |

So it is not the ISA variant, not the model, not the split mode, and not the precompiled
metallib -- removing the precompiled libraries and forcing a runtime build reproduces it exactly.
It is in how the fork's kernel source is assembled into the library.

## Why this matters more than the throughput number

`llama_init_from_model: enabling flash_attn since it is required for SPLIT_MODE_TENSOR` -- the
engine says tensor split **requires** flash attention. The vector flash-attention kernel is the
fast path; with its pipeline missing, attention falls back.

That means the 14B throughput comparison in
`14b-serves-but-does-not-split-2026-10-19.md` was taken on a build where a feature tensor split
depends on is silently broken. Both modes pay the same penalty, so the comparison is not
*biased* between them -- but it is a measurement of two degraded configurations, and a ~1 tok/s
result from a degraded configuration was never going to separate two split strategies.

The earlier "Reading 1: the split is degenerate" leaned on that number. It does not survive this.
What survives is the weaker, checkable statement: the log names one device and one aggregate
buffer, so the split is not *demonstrated*. The throughput evidence is withdrawn.

## What this is not

It is not established that the missing pipeline *causes* ~1 tok/s. That is a plausible mechanism,
made more plausible by tensor split requiring flash attention, but it has not been measured
against a build where the kernel links. Calling it the cause without that comparison would be
the same mistake this project keeps making: naming a mechanism from a correlation.

## Consequence

This is a defect in the fork's own headline kernel, present in every build produced here, on the
exact feature the round is trying to claim. It outranks the capability matrix: a tensor split
that runs without its vector flash-attention kernel is not the thing that was going to be
benchmarked.
