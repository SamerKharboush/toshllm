# The assertion, the instrument, and the wrong binary

## The abort is in the meta backend's split state, not "Metal lacks tensor split"

Stderr before the SIGABRT, verbatim:

```
W common_fit_params: not fitting params to free device memory: automatic fitting is not
  implemented for --split-mode tensor; continuing with the parameters as given
...
ggml_abort
  ggml_backend_meta_get_split_state(...)
  ggml_backend_meta_buffer_init_tensor_impl(...)
  ggml_backend_meta_buffer_init_tensor(...)
```

The `.ips` report adds only `abort() called` / `SIGNAL 6`; the message is on stderr, which is
where it has to be read from. The failing symbol is **`ggml_backend_meta_get_split_state`** --
the multi-device split-state computation -- reached from buffer init. That is a quotable
capability statement, but it is narrower than "tensor split unsupported": the engine accepts
the flag, warns that it cannot auto-fit memory, and then aborts while computing split state.

`-sm row` is a different failure: exit 1, a clean rejection, no signal.

## The instrument question resolves: gfx600 is formatted, not stored

`grep -ac gfx600` returns 0 in both binaries; `grep -ac gfx` returns 3 and 4. The log prints
`amdgpu_gfx600`, which no string table can contain because it is assembled at runtime. The
earlier "one instrument is lying" section was wrong to call that a contradiction. It was a
literal-prefix match on a formatted value.

My first manifest extraction also returned 0 names while the logs contained 31 kernel-ish
lines: the regex was wrong, not the binaries. Third instrument failure this round, same class
as the others.

## The finding that matters: the A/B has been comparing versions, not branches

Normalised diff of two `-ngl 99 -sm layer` runs, 4409 log lines each:

```
< baseline: ToshLLM engine 0.87.26   (app standalone)
< baseline: AppleClang 21.0.0
---
> ours:     ToshLLM engine 0.87.24-beta.1 (app standalone)
> ours:     AppleClang 17.0.0
```

**`dist/ToshLLM.app` is the stale 0.87.24-beta.1 build.** It is the same bundle the README
still advertises. Every "ours" measurement taken from it so far would have compared a
different *release*, not a different *branch*, and the graph differs accordingly: 1633
normalised lines, with the baseline emitting `out_ids` GET_ROWS nodes where ours emits
`attn_inp_kq_mask` / `FLASH_ATTN_EXT` nodes.

The A/B cannot run until the 0.87.26 engine is built from this branch. That is ticket 50a's
build, and it now blocks the measurement rather than merely preceding it.

## Free confirmation: the noavx2 label is behavioural

```
< baseline: MTL : EMBED_LIBRARY = 1 | CPU : SSE3 = 1 | SSSE3 = 1 | LLAMAFILE = 1 | ACCELERATE = 1 | REPACK = 1
> ours:     MTL : EMBED_LIBRARY = 1 | CPU : SSE3 = 1 | SSSE3 = 1 | AVX = 1 | F16C = 1 | LLAMAFILE = 1 | ACCELERATE = 1 | REPACK = 1
```

The baseline reports no `AVX` and no `F16C`; our build reports both. That is the runtime
counterpart to the disassembly audit, from the engine's own system_info, and it is the first
evidence for the noavx2 label that is not a byte count.

## Correction to the previous evidence file

`split-mode-and-markers-2026-10-19.md` calls wave64 "doubtful" on the strength of string
counts. Both binaries emit:

```
ggml_metal: wave64 decode ON: quantized/f16/bf16 mat-vec on GPU
ggml_metal: aligned mat-vec reads ON by amdgpu_gfx600
```

So the shipped 0.87.26 build does carry wave64 decode. Whether that is upstream's own work or
shared lineage remains unresolved, and string counts cannot settle it. One kernel name taken
verbatim from `patches/llama/metal/0006-toshgemm.patch` and grepped in both manifests is the
test that can.
