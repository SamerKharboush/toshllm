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
