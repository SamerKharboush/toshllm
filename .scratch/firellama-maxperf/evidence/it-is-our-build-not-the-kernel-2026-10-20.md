# The bisect says it is our build, not the kernel and not a shipped defect

## The four engines

| engine | version | sha256 | AMD FA kernel present | pipeline failures |
|---|---|---|---|---|
| `dist/ToshLLM.app` (ours, stale) | 0.87.24-beta.1 | `c2d9ba79` | 27 refs | **0** |
| `/Applications/ToshLLM.app` | 0.87.26 | `c232e476` | 27 refs | **0** |
| ours@AVX1 (this session) | 0.87.26-beta.1 | `fce9e70e` | 27 refs | **1** |
| ours@SSE2 (this session) | 0.87.26-beta.1 | `b8ef1158` | 27 refs | **1** |

Both shipped apps run clean. Both fresh builds drop the kernel. **All four carry the kernel.**

So the previous evidence file was wrong on two counts, both now corrected:

1. It said "this has shipped in every beta / is a long-standing defect". It has not -- both
   shipped binaries report zero failures on the same model and the same machine.
2. It said the kernel is ours and not upstream's. `grep -rl` found it absent from pristine
   upstream at the pin, yet a shipped vendor build carries 27 references to it -- so the
   kernel *source* ships in the products and links fine there.

What the evidence actually supports: **the defect is produced by this build process**, not by
the kernel source and not by a patch. Two of our builds have it; two vendor builds of
substantially the same code do not.

## Why removing `bin/kernels` changed nothing

The engine reports `MTL : EMBED_LIBRARY = 1` -- the Metal library is embedded in the binary at
build time by `-DGGML_METAL_EMBED_LIBRARY=ON` (`scripts/build-engines.sh:112`). Deleting
`bin/kernels/` therefore removes libraries the engine may never load, and leaves the embedded
one untouched. My earlier "it is not the precompiled metallib" conclusion was drawn from a test
that could not have changed the outcome -- the fourth check this project has run that could not
fail.

The build also compiles each kernel source separately:

```
scripts/build-engines.sh:199  "$METAL_COMPILER" -O3 -mmacosx-version-min=14.0 -std=metal3.1 \
scripts/build-engines.sh:200      -DGGML_METAL_EMBED_LIBRARY -DGGML_METAL_HAS_BF16 \
```

`-DGGML_METAL_EMBED_LIBRARY` is passed as a **preprocessor define** to a Metal compile, while
upstream treats it as a CMake option. That is the shape of cause B in the discriminator: two
compilations that do not share their options, one of which produces a module with an empty data
layout. It is a candidate, not a finding -- it has not been tested by rebuilding without it.

## What is established, and what is not

**Established:** the failure is a property of the build this session produced, not of the
source, not of the ISA, not of the model, not of the split mode.

**Not established:** which build step causes it, and whether the missing kernel is what bounds
14B at ~1 tok/s. The mechanism is still unmeasured.

## Harness change

`preflight()` in `tools/ab.sh` now counts `failed to create pipeline state` in each serve log and
fails on a non-zero count. Today's build is the positive control: it logs one, so the gate is
known to be able to trip. A build that silently drops a kernel can no longer produce a row.
