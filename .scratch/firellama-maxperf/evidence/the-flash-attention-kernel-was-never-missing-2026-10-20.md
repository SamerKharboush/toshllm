# The flash-attention kernel was never missing: its half-size twin carries the decode

## The error has two sentences, and the record read the wrong one

Every run of this engine prints, once per kernel:

```
E ggml_metal_library_compile_pipeline: failed to create pipeline state:
  base = 'kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64'
E ggml_metal_library_compile_pipeline: Error Domain=CompilerError Code=2 "
Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-...'
SC compilation failure
GPGPU, exceed the local data storage limit"
```

The first line of the driver's message is the preamble. The refusal is the last line: **the
local data storage limit**. The 64-lane flash-attention kernel asks for about 33 KB of
threadgroup memory (`sh_acc` is `NG*SAS` float4, and the kernel file says so at
`kernels/fa.metal:337`), and a GCN 1.0 threadgroup gets 32 KB.

The data-layout sentence is a red herring that the earlier record
(`our-own-flash-attention-kernel-does-not-build-2026-10-20.md`) took for the cause. It read
"the kernel's module carries an empty data layout" and concluded "the kernel is silently
unavailable every time the engine runs".

## The host already recovers, and it recovers into a kernel that runs

`fa.metal` ships a twin of every 64-lane vector kernel with half the simdgroups, and the host
takes it when the driver refuses the wide one (`ggml-metal-ops.cpp`, `TOSH_FA_AMD_LDS32=1`
forces it on any wave64 card). Ticket 35 measured the twins on this card: they build, at
16,576 to 17,920 bytes of threadgroup memory, and they do not exceed the limit.

So the wide kernel is refused, the twin is used, and the run continues. The log never said
which kernel it ended up on.

## Measured: the default already runs the twin

Three cells, interleaved round by round, one server at a time, n=3 each, the headless D700,
`Qwen3-8B-Q4_K_M` (head size 128, f16 KV), `-ngl 99 -sm layer -c 4096 -t 8`, 32 generated
tokens at temperature 0. Engine sha256
`fce9e70e875bcb69cb0b3cf358f41ddcefa41c00c4a4a5cf157386c5d593ef70`.

| cell | tok/s | sd | n | pipeline refusals | "not instantiated" |
|---|---|---|---|---|---|
| default | 8.2632 | 0.0210 | 3 | 1 | 0 |
| `TOSH_FA_AMD_LDS32=1` (twin forced) | 8.2719 | 0.0015 | 3 | 1 | 0 |
| `TOSH_FA_AMD_DISABLE=1` (AMD attention off) | 7.6384 | 0.0691 | 3 | 0 | 0 |

- **default vs twin forced: +0.0087 tok/s (+0.11%), 0.7 sigma of the pooled noise.** Forcing
  the twin changes nothing, so the default was already running the twin.
- **default vs the AMD attention path off: +0.6248 tok/s (+8.18%), 15 sigma.** The path that
  survives is the AMD one, and it is worth 8% of the decode.

The third cell is the control that makes the first one mean something: it is the only cell
that changes what runs.

One more thing fell out of the third cell: with the AMD attention path off, this model
**refuses to load under a tensor split** ("This model has no two-way tensor split. Restart
with --split-mode layer."), because the attention op the generic path builds is not one the
tensor split can cut. The AMD attention path is what makes the tensor split work here.

## What is wrong in the logs, then

Not the kernel: the log. Two things.

1. The refusal is printed as an **error** by the shared compile helper, on every process, for
   a refusal the host handles two lines later. On the 35B prefill path the same refusal was
   recompiled **50 times** in one run, because that call site does not go through the cache
   the vector path uses (`ggml_metal_fa_amd_pipeline`, which remembers a refusal by name).
2. The release note built on `our-own-flash-attention-kernel-does-not-build-2026-10-20.md`
   says the kernel is missing. It is not. The vector attention runs, in its twin form.

## The change

`patches/llama/metal/0039-fa-refusals-fall-back-loudly.patch`:

- a refusal the caller can plan for is no longer logged as an error: the compile helper grew
  a quiet variant, and the attention path says which kernel it is using instead
  (`the driver refused <kernel>; using <twin>`), once per kernel rather than once per layer;
- the prefill path goes through the same refusal cache, so a refused kernel is asked once per
  process instead of once per layer per prompt;
- a kernel with **no** fallback is now an error, and it says so: `... is not instantiated;
  using the generic kernels`. That is the string the release gate counts.

`tools/ab.sh` counted `failed to create pipeline state`, which is the refusal the code
recovers from, so today's build failed the gate that was written to catch a *missing* kernel.
The gate now counts the drop, and it proves itself: `TOSH_FA_AMD_NSG_*=9999` asks the
attention path for more threads than the kernel admits, which is the same drop, and the
counter has to read non-zero on that run or the preflight fails.

### The control found a defect in the change, which is the point of having one

The first version of the patch printed the refusal line and the drop line through one
once-per-kernel guard, keyed by the kernel name. The refusal came first and took the key, so
the drop line was swallowed: on a forced drop the counter read zero, and the control said the
check could not fail. The guard now keys on the kind of line as well as on the kernel.

```
preflight[baseline]: -ngl 0 served, produced 32 tokens
preflight[baseline]: -ngl 99 served, produced 32 tokens
preflight[baseline]: drop counter reads 1 on a forced drop (the control passes)
```

And the patched engine on the 8B, same card, same flags as the table above:

```
mean=8.2687 sd=0.0032 n=3
failed to create pipeline state : 0
is not instantiated             : 0
the driver refused              : 1
using the generic kernels       : 0
W ggml_metal_op_flash_attn_ext: the driver refused kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64; using kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32
```

8.2687 against the 8.2632 of the unpatched build: the change is about the log, not the speed.

## What this does not establish

- The wide kernel still does not build on this card, and the twin is a different kernel: the
  decode number above is the twin's number. Whether the wide kernel would be faster is not
  measured, because it cannot run here.
- The prefill kernel for head size 256 wants 54.5 KB of threadgroup memory
  (`BQ*(DK+4) + max(BK*(DK+4), DV*(BK+4)) + BQ*(BK+4)` halves at `DK=256, BQ=32, BK=64`), so
  the 35B's prefill runs on the tile kernel. A variant with a smaller key block fits
  (27.25 KB at `BQ=16, BK=32`) and is not wired up. That is the separate ticket the release
  notes point at, with its payoff still to be measured.
