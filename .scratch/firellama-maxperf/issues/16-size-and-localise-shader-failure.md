# 16: Size and localise the shader failure

**What to build:** Every server start on this machine prints a Metal shader compilation failure. It is present in both arms of every differential experiment, which makes every patched-versus-pristine delta on record a comparison of two substituted builds. This is the only open item that can retroactively invalidate published numbers, and it is the only one that survives a fresh checkout. The ticket ends with either a size for its share of a decode window or a statement that it is off the decode path.

**Blocked by:** None (can start immediately).

**Status:** partial 2026-10-17 — the failing kernel is named and located on the decode path. Two acceptance criteria are not met: its share of a decode window has not been measured, and whether published figures must be re-flagged is therefore undecided. Do not treat this ticket as closed.

- [ ] The failure is localised from the compiler's own error text, giving a source file and line, rather than inferred from the engine's flattened error string
- [ ] The kernel that fails to compile is named, and whether something substitutes for it at runtime is stated
- [ ] One measurement sizes the failed path's share of a decode window, or states that it does not appear in it
- [ ] The finding says whether any published figure must be re-flagged as measured against a substituted build
- [ ] A note records the fingerprint of the shader binaries the current numbers were measured with

## Result

**The failing kernel is named in the engine's own log**, one line before the error text:

```
E ggml_metal_library_compile_pipeline: failed to create pipeline state:
  base = 'kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64'
  Error Domain=CompilerError Code=2 "SC compilation failure"
  GPGPU, exceed the local data storage limit
  Linking two modules of different data layouts: '' is '' whereas '1' is 'e-p:64:64:64-...'
```

Two distinct faults, not one:

1. `exceed the local data storage limit` — the kernel asks for more threadgroup memory than the device grants.
2. `Linking two modules of different data layouts` — an LLVM datalayout mismatch between two bitcode modules, where one carries an empty target datalayout.

**It is on the decode path.** The `_vec_` in the name is the single-query-token flash-attention variant, which is the one generation uses; the batched variant is the prefill path. So a substituted attention kernel has been present in every decode measurement taken on this machine.

**Why this outranks everything else:** `TOSH_FA_AMD=1` is what `kernel_flash_attn_ext_vec_amd_*` comes from, and on a tensor split that variable is *required* — the configuration cannot build without it. So the mechanism that makes the measured setup possible is the mechanism that is failing to compile one of its variants, on the path every decode number was taken from.

## What is established and what is not

Established: which kernel, which two failure modes, and that the variant is the decode one. Not established: **what ran in its place.** A failed pipeline creation means this variant did not run; whether the engine fell back to another f16 variant, to a non-wave64 kernel, or to CPU attention is not known, and no published delta can be re-flagged as substituted until it is.

## A route that is closed

`log stream --predicate 'process == "MTLCompilerService"'` captured nothing but the service's own XPC teardown, so the compile happens in-process and the recommended log-predicate route does not yield a `program_source:LINE:COL`. The engine's log line is the best available locator, and it is better than expected: it names the kernel outright.

## A probe that said nothing

`nm` and `strings` were run against `bin/llama-server` and found neither the error strings nor the compile symbols. The error text appears in the log, so the strings exist somewhere — they are in the bundled dylibs, not the executable. That probe was pointed at the wrong artifact and carries no information either way.

## Handover

`metallib-fingerprint-2026-10-17.txt` records SHA-256 for all 41 embedded metallibs, including `fa_w64.metallib`, `fa_vec_f16.metallib` and `mul_mv_w64.metallib`. That is the fingerprint every number in this record was measured against.
