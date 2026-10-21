# 27: Which kernel executes decode attention

**What to build:** the identity of the kernel that actually computes decode attention on this builder, given that the AMD wave64 dk128 f16 variant fails to compile and its failure is returned in the shape of a success with a nil pipeline. Until this is answered, no published decode delta can be classified as clean or as contaminated, because the substitute is unknown.

**Blocked by:** 16 (partial — the failing kernel is named).

**Status:** ready-for-agent

- [ ] The dispatch site for flash attention is read, and whether it guards on a nil pipeline is stated from the code
- [ ] If it guards, the path taken instead is named, and whether that path is a different GPU kernel or host-side work
- [ ] If it does not guard, that is stated plainly, with what a nil pipeline with zero threadgroup dimensions does when encoded
- [ ] A runtime observation confirms the code reading, rather than the code reading standing alone
- [ ] The finding states which published decode figures were produced with a substitute in the path and which were not
- [ ] The fork's own rule is applied to the conclusion: a success that silently returns wrong data has no fallback

## Partial: the selector, and the fork already knows

The FA support predicate lives at `ggml-metal-device.m:2754-2795`. Its own comment, verbatim:

```
// AMD dGPUs report no simdgroup_mm and miscompile the upstream vec kernel, so FA is
// allowed only for the KV pairs our own vec kernel instantiates. This sits before
// the K==V gate because that kernel takes K and V independently.
```

So the miscompilation of the upstream vector kernel on AMD is **already known to the fork** — it is the reason `TOSH_FA_AMD` exists at all. The fork's answer was to allow FA only for the KV pairs its own vec kernel instantiates.

The gate:

```
const bool fa_amd_width_ok = dev->props.simd_width == 32 ? has_simdgroup_reduction : wave64_decode;
if (TOSH_ENV("TOSH_FA_AMD") != NULL && !has_simdgroup_mm && fa_amd_width_ok && (...)) {
    ...
    const bool dk_ok = dk == 64 || dk == 128 || dk == 256 || dk == 512 || ...;
    const bool k_std = (kt == GGML_TYPE_F16 || kt == GGML_TYPE_Q8_0 || kt == GGML_TYPE_Q4_0 || k_turbo);
    const bool v_std = (vt == GGML_TYPE_F16 || vt == GGML_TYPE_Q8_0 || vt == GGML_TYPE_Q4_0 || v_turbo);
    if (simple) { ... }
```

`dk == 128` is in `dk_ok`. `F16` is in both `k_std` and `v_std`. So **the gate admits exactly the combination that fails to compile** — dk128, k f16, v f16, on a wave64 part. The selection logic and the failing variant agree; the variant fails *after* being legitimately selected.

## Still not established

Whether the dispatch site guards on a nil pipeline. That is the remaining acceptance criterion and it decides whether a substitute kernel ran or whether the encode was a no-op. The fork passed a 256-token logprob parity check, which is evidence that attention was computed correctly by something — evidence for a guard, not proof of one.

## Correction: two causal claims retracted, and a worse finding in their place

**Retracted.** There is no zero-dimension dispatch and no per-request recompile.

- The guard is at `ggml-metal-ops.cpp:5341`: `GGML_LOG_WARN("%s: %s is not instantiated; using the generic kernels\n", ...)`. Both failure branches fall through to the generic kernels, so the zeroed `nsg/nr0/nr1/smem` are never used as dispatch dimensions on this path.
- The recompile does not happen. `ggml-metal-ops.cpp:4527-4539` carries a static negative cache whose comment is verbatim: *"A kernel the driver refuses to build (local memory over the device limit) is refused every time, and asking again costs a compile per layer and token."* Once per process per name. That comment also names the cause exactly: local memory over the device limit.
- Corrected blast radius: any failing pipeline **not** fetched through that cached accessor.
- Free falsifier worth keeping: a published tok/s in the normal range is positive evidence the compile is not on the per-token path.

**What is actually serious.** The fallback target is the generic vec kernel, and the fork's own comment at `ggml-metal-ops.cpp:4960` says: *"AMD discrete GPUs miscompile the templated vec kernel, so route attention (decode..."*. So the guard catches a nil pipeline and hands the work to a kernel the fork documents as miscompiled. A guard that falls back onto a kernel you believe is broken is not a guard, and it is the state `ggml-metal-context.m` refuses to ship for the optional peer copy: *"a success that silently returns wrong data has no fallback."*

**Asymmetry to record:** the AMD path degrades quietly behind a WARN. The generic path does not guard — it dereferences `pipeline.pipeline->obj` in an assert, so a nil there aborts rather than degrading.

## Refuted: the missing-instantiation hypothesis

Checked directly, no GPU needed:

- All four macros **are defined** in the applied tree: `FA_AMD_INST_W64` at `fa.metal:316`, `_S` at `:319`, `_WG` at `:322`, `_LDS` at `:339`. Uses: 15 of `_S`, 9 of `_WG`.
- The requested name **is present** in the built metallibs. `strings build-static/bin/kernels/*.metallib` returns `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64` alongside `_wg32`, `_w64_lds32` and `_w64_wg32_lds32` variants.
- The engine's error is `failed to create pipeline state` — the `!obj` branch — not `failed to compile pipeline`, the `!mtl_function` branch. The function **was found**; pipeline creation then failed.

So it is not a missing host name and not a name mismatch. It is a genuine compile failure of an instantiated kernel, and the two faults are the ones already recorded: threadgroup memory over the device limit, and a datalayout mismatch linking two bitcode modules.

## Third instance, and a fourth that is mine

This ticket asserted a mechanism from a local reading without checking the caller. That is the third time this session, after the 80/20 share and the 18% overhead claim.

A fourth instance belongs to me and produced the false "macros are undefined" evidence: an earlier grep was piped through `head -14`, the patch-file hits sorted ahead of the tree's, and I read the truncation as the result. The macros were defined the whole time. Truncated output is not evidence.
