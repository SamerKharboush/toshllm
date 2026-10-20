# 56: the flash-attention kernel that never links

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

Every build this branch produces logs:

```
E ggml_metal_library_compile_pipeline: failed to create pipeline state:
  base = 'kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64'
E ... Error Domain=CompilerError Code=2 "Linking two modules of different data layouts:
  '' is '' whereas '1' is 'e-p:64:64:64-i1:8:8:8-...'"
```

The engine continues and serves, so the kernel is silently absent. The engine also states
`enabling flash_attn since it is required for SPLIT_MODE_TENSOR`, so the feature tensor split
depends on is the one that is missing.

Bisected: `dist/ToshLLM.app` (0.87.24, `c2d9ba79`) and `/Applications/ToshLLM.app` (0.87.26,
`c232e476`) both log **zero** failures; both of this branch's builds (`fce9e70e`, `b8ef1158`)
log one, and an upstream build from pristine source at the pin logs zero. The defect is produced
by this branch's build, not by the source and not by a shipped product.

## Change

Discriminate and fix, in this order:

1. Cause A (two modules linked): the build script deliberately emits one metallib per kernel
   source -- "they cannot be linked into one metallib: the sources share helper names" -- and
   the runtime stitches them. If the failing module is one of those, inline it so there is
   nothing to link.
2. Cause B (one module, wrong options): `scripts/build-engines.sh:199-200` passes
   `-DGGML_METAL_EMBED_LIBRARY` as a **preprocessor define** to a Metal compile, where upstream
   treats it as a CMake option. Rebuild without it, or make both compilations share one
   `MTLCompileOptions`.

## Done when

- The error is absent from stderr in all six configurations (0.6B/8B/14B x tensor/layer).
- `strings` on the built metallib shows the kernel, and a pipeline is created for it.
- `tools/ab.sh` preflight fails a build that logs a pipeline failure -- already landed, with
  today's build as the positive control.
- A 14B `-sm tensor` before/after throughput pair, reported as the removal of a defect and
  not as a discovery.

## Answer

