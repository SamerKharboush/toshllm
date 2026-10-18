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

## Follow-on: what happens instead, from the code

`ggml_metal_library_compile_pipeline` (ggml-metal-device.m) initialises its result with `pipeline = nil` and every threadgroup field zero, then:

```
res.pipeline = ggml_metal_pipelines_get(lib->pipelines, name);
if (res.pipeline) { unlock; return res; }        // cache hit
...
id<MTLComputePipelineState> obj = [device newComputePipelineStateWithFunction:mtl_function error:&error];
if (!obj) {
    [lib->lock unlock];
    GGML_LOG_ERROR("... failed to create pipeline state: base = '%s', name = '%s'", ...);
    if (error) GGML_LOG_ERROR("%s: %s", __func__, [[error description] UTF8String]);
    return res;                                   // <-- pipeline still nil, dims still zero
}
```

Three facts follow directly:

1. **Failure is returned in the shape of success.** The caller receives a struct with a nil pipeline and zero threadgroup dimensions, with no error flag. Nothing distinguishes it from a valid return except the log line.
2. **The failure is not cached.** The early-return happens before the pipeline is inserted into the library, so every subsequent request for this kernel recompiles it and re-fails. That is why the same failure appears more than once per start — probably one kernel requested repeatedly, not several kernels.
3. **There is no fallback.** The log announces none, and the code attempts none: it does not retry another variant, does not disable the path, and does not substitute a generic kernel.

The fork warns about exactly this pattern elsewhere in the same tree. In `ggml-metal-context.m`, guarding the optional peer copy, it says: *"a success that silently returns wrong data has no fallback."* The compile path does the thing that comment rules out.

## Still not established

**Which kernel actually executes decode attention.** Candidates, none yet eliminated: the dispatch site guards on a nil pipeline and takes another path (a different variant, or a host-side attention); or the nil pipeline is encoded against and does nothing. The engine produces coherent output and passed the 256-token logprob parity check, so *something* computes attention correctly — which is evidence for a guard, not proof of one.

This is now ticket 27.

## Answer, from ticket 35

The question "what ran in its place" is answered. The kernel selector requests the
plain `..._w64` name first, and falls back to the same kernel's `_lds32` twin at half
the simdgroups when that build fails. The refusal is memoised per process, so it costs
one failed compile, not one per layer or per token.

The split is exact and not a size effect. Refused plain widths: {64, 128, 256, 512}.
Building plain widths: {40, 72, 80, 160}. Those are precisely the widths that have an
`_lds32` twin and those that do not, so the correlation is with the twin's existence
rather than with the request size. The largest request that builds is 23552 bytes,
9216 under the 32768 ceiling.

Evidence: .scratch/firellama-maxperf/evidence/threadgroup-memory-2026-10-18.md
