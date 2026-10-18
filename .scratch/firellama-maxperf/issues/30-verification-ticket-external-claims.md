# 30 - Standing verification ticket: external claims, and the agent that checks them

Status: open, recurring
Date: 2026-10-18

## Why this exists

Every externally supplied technical anchor in this project so far has been
checked against the machine or the source rather than taken on trust, and a
large share of them failed. The failure mode is consistent and worth naming: a
claim arrives that is plausible, specific, and wrong in a way only a check
reveals. Accepting one has already cost this project a retraction cascade and
one void measurement run.

The rule this ticket encodes: any claim that would change what gets built is
checked before it changes anything, and the check is recorded here with its
verdict and its source.

## The agent

Web verification is delegated to a worker subagent given a numbered claim list.
It returns VERIFIED / FALSE / UNVERIFIABLE per claim with a primary source and a
quote. Primary sources only: project code, project docs, GitHub issues, Apple
documentation. Search results alone are not accepted as evidence for a claim
about code. The verdicts are pasted below.

Verdicts are recorded even when they confirm the claim, because "this one was
right" is information about the source's reliability.

## Log

### Round 1 (2026-10-17 and 2026-10-18)

Checked locally against this machine and tree:

| claim | verdict | how it was checked |
|---|---|---|
| D700 lacks Metal3 | TRUE | `MTLCopyAllDevices` + `supportsFamily:` via tools/metal-probe |
| D700 has threadExecutionWidth 64 | TRUE | same probe |
| patches/llama/metal/ exists | TRUE | directory listing, 15 patches |
| 0001-amd-backend-host.patch exists | TRUE | find |
| 0004-matvec-wave64.patch exists | TRUE | find |
| 0012-older-gcn-and-macos12.patch exists | TRUE | find |
| 0013-vram-budget-and-private-mirror.patch exists | FALSE | not present anywhere; quant/0013 is turbo-kv. The VRAM budget logic is in 0001 and 0002 |
| patches/llama/metal/ holds 16 patches | FALSE | it holds 15 |
| branch is 34 commits behind origin/main | FALSE | `git rev-list --count HEAD..origin/main` is 0; it is 19 ahead |
| upstream toshllm HEAD is 1559d9b | FALSE | `git ls-remote upstream HEAD` is 523b814ac8cc61d80afbc73cece581c34234658b |
| toshllm-work/iron-llama-rc1 and toshllm-work/toshllm-ours exist | FALSE | no such directory, and no ~/toshllm-work |
| GGML_METAL_VRAM_BUDGET_MB exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_N_CB exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_FORCE_PRIVATE exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_DEVICE_INDEX exists in the fork | TRUE | 2 files reference it |
| GGML_METAL_CONCURRENCY_DISABLE exists in the fork | TRUE | 1 file references it |
| this CPU has no AVX2 and no FMA3 | TRUE | sysctl leaf7_features and features |
| llama.cpp #15228 exists and is about Metal3 on Mac Intel and Radeon | TRUE | fetched the issue |
| iRon-Llama exists | TRUE | github.com/Basten7/iRon-Llama, README targets W6800X Duo |

Delegated to the web-verification agent, round 1: issues #19610 and #26949, the
`has_simdgroup_reduction` gate and its family condition, whether Apple documents
the D700's Metal family, whether `ggml-metal-gcn` exists as a project, the
current HEADs of both toshllm repositories, and what iRon-Llama claims to
support. Verdicts appended below when they return.

## The one that would have done damage

A claim arrived that without `has_simdgroup_reduction` "Metal backend is
mathematically impossible, not tuneable", which would have required declaring
this fork's working GPU path impossible. It is false as stated, and the
evidence is on this machine: the fork compiles 19 Metal pipelines for a single
0.6B forward pass, reports zero CPU fallbacks, runs `kernel_mul_mm_q8_0_f32_w64`
as a GPU matmul, is deterministic run to run (cosine 1.0000 against itself),
and reproduces the published throughput to 0.13% on pp512.

The accurate statement, which the fork's own maintainer makes in #15228, is that
the *current upstream implementation* requires it. That is a codebase
constraint, not a hardware one, and it is the constraint this fork exists to
lift.

### Round 1 verdicts (web agent, primary sources)

| # | claim | verdict |
|---|---|---|
| 1 | llama.cpp #19610 reports a Vulkan/RADV DeviceLost crash on GCN 1.0 with full offload | VERIFIED. Titled for Tahiti/HD 7900/R9 280X, hardware listed as 2x FirePro D700 on Arch Linux. Closed next day as a duplicate of #19615. |
| 2 | llama.cpp #26949 reports GGML_ASSERT(buf_src) from the page-alignment requirement | VERIFIED. iMac Pro 2017 + Vega 56. Closed stale, bug-unconfirmed, fix never merged. |
| 3 | upstream gates GGML_OP_MUL_MAT and MUL_MAT_ID on has_simdgroup_reduction | VERIFIED, but through a helper: `ggml_metal_supports_mul_mat_op(has_simdgroup_reduction, op, true, ...)`, not a direct `&&` in the case bodies. |
| 4 | the flag is only true for Apple7 or Metal3 | VERIFIED. Set from `supportsFamily:MTLGPUFamilyApple7` then ORed with `MTLGPUFamilyMetal3_GGML` (5001). Nothing else assigns it and there is no env override. |
| 5 | the D700 supports Metal 2 and not Metal 3 | Machine-level only. Apple states this for "Mac Pro introduced in late 2013 or later"; the Metal Feature Set Tables PDF contains no AMD card names at all and no Mac GPU-family table. The D700 card is never documented. Inference, not documentation, so the supportsFamily: probe is the stronger evidence. |
| 6 | `ggml-metal-gcn` is a project to build on | **FALSE.** No repository by that name. GCN Metal work is real but under different names, notably `leolebkuchen/llama.cpp` branch `wave64-radeon-vii`. |
| 7 | upstream toshllm is at 1559d9b | **FALSE.** HEAD is 523b814 "release: 0.87.26", 2026-10-17. 1559d9b is real but 50 commits behind (the Ukrainian translation merge). |
| 8 | SamerKharboush/toshllm is public, default branch main | VERIFIED. HEAD 8a238c4, 2026-10-15. |
| 9 | iRon-Llama targets Metal3-class hardware | VERIFIED. Targets W6800X Duo, "designed to be MetalV3 compatible", and never mentions FirePro, D700, GCN or Vega. |
| 10 | upstream has merged or documented pre-Metal3 AMD Metal support | **FALSE.** Master still gates on the flag, so those ops fall back to CPU. PR #19527 "Metal backend performance on AMD discrete GPUs" has been open and unmerged since 2026-02-11. #15228 closed not-planned; #25866 and #26949 closed stale. docs/build.md never mentions the gate. |

Claims that failed verification: 6, 7, 10.

## What this changes

1. **The sync target is upstream 0.87.26, not 1559d9b.** This machine reports engine
   0.87.24-beta.1. That is a real gap and it is the first correct statement of
   deliverable 6. Worth a separate ticket.

2. **A second independent GCN Metal effort exists**: `leolebkuchen/llama.cpp`,
   branch `wave64-radeon-vii`, described as "wave64: coherent, fast Metal LLM
   inference on AMD GCN/Vega Macs". It is not called ggml-metal-gcn and it is not
   a clean-room backend, but it is prior art on the same problem and has not been
   read here. Worth reading before any new kernel work.

3. PR #19527 upstream, open and unmerged since February, touches Metal
   performance on AMD discrete GPUs. Unread. If it contains anything this fork
   already solved independently, that is worth knowing in both directions.

### PR #19527 reviewed, mechanism by mechanism

Open since 2026-02-11, one commit (`e4597961`), 3 files, +78/-9, all inside
`ggml/src/ggml-metal/`. Head not rebased in eight months. **Zero maintainer
reviews or comments ever**; the only comment is a third-party hardware report.
Labelled `vibe-coded` three minutes after opening.

**It does not touch the `has_simdgroup_reduction` gate at all.** The string
`simdgroup` does not occur in the diff; `ggml_metal_supports_mul_mat_op` and the
flag initialisation are untouched. It works entirely inside the gate. Its test
hardware is a Radeon Pro 5300M (RDNA 1), where the gate is already satisfied.
It never mentions the D700, GCN, Tahiti or pre-Metal3 anywhere.

Two mechanisms:
1. Serial dispatch for non-Apple GPUs, keyed on `!supports_gpu_family_apple7`.
2. `use_managed_buffers = !has_unified_memory` with
   `MTLResourceStorageModeManaged`, `didModifyRange:`, `synchronizeResource`,
   and a changed `clear()` guard.

Mechanism 1 **already exists in this fork**, same stated cause, different
predicate: `patches/llama/metal/0001-amd-backend-host.patch:249-254` keys on
`has_unified_memory` instead of `!supports_gpu_family_apple7`. The fork's comment
names the cause outright: "discrete GPUs (AMD) corrupt their output with a
concurrent encoder: the driver does not honour the memory barrier."

Mechanism 2 is absent from the fork entirely: `MTLResourceStorageModeManaged`
has zero matches across `patches/`. The fork uses `Shared` plus write-combined
staging instead. If it ever binds, it binds only on the deferred
`buffer_from_host_ptr` path, which the fork already disables for the D700.

**Consequence: nothing actionable.** The PR cannot substitute for the fork's
kernel work, and its one shared mechanism is already present.

### The line that actually lifts the gate

Worth recording, because it is the fork's central claim:

    patches/llama/metal/0003-wave64-reductions-and-quant-loads.patch:404-406
    -            return has_simdgroup_reduction && ggml_is_contiguous(op->src[0]);
    +            // wave64: nsg and shmem are sized by the real width, so the reduction is width-agnostic.
    +            return (has_simdgroup_reduction || wave64_decode) && ggml_is_contiguous(op->src[0]);

`wave64_decode` is the mechanism. That single disjunct is the difference between
this fork doing matrix multiply on the GPU and stock llama.cpp assigning it to
the CPU, which is what the 1.28788-versus-1e-5 parity result and the 7-versus-19
kernel-compile count both measure.

### wave64-radeon-vii reviewed: it is not independent prior art

The brief said to cross-check against "the same problem, independent author". It is
not independent. `leolebkuchen/llama.cpp` (default branch `wave64-radeon-vii`,
created 2026-07-18, two commits on an upstream base of `1593d568`) shares with this
tree, verbatim:

| artifact | external | local |
|---|---|---|
| `// simdgroup reduction kernels produce corrupted output on AMD RDNA 2 (e.g. RX 6700 XT)` | `device.m:774` | `0001-amd-backend-host.patch` |
| `probed SIMD-group width = %d (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)` | `device.m:767` | `vendor/.../ggml-metal-device.m:1805` |
| env var set | `GGML_METAL_WAVE64_DECODE`, `GGML_METAL_DEVICE_INDEX`, `GGML_METAL_SIMDGROUP_REDUCTION_DISABLE`, ... | the same |
| prop names | `wave64_decode`, `use_mm_manual` | the same |
| function-constant slots | `FC_MUL_MV + 5`, `FC_MUL_MM + 6` | the same |
| kernel name | `kernel_flash_attn_ext_vec_amd` | the same |
| project naming | its `HOWTORUN.md` points at `toshllm/vendor/llama.cpp-merged` | this repo |

Direction cannot be proven from these artifacts, but everything checkable is
consistent with this fork being that lineage continued on a newer base, and a
strict superset of its mechanisms. So this is ancestor-versus-descendant, not a
cross-check: agreement between them is not independent corroboration and must not
be reported as such.

Its GEMM work is smaller than the fork's, not a different answer: ~100 lines inside
`kernel_mul_mm`/`kernel_mul_mm_id` replacing `simdgroup_multiply_accumulate` with
per-lane register MACs behind `FC_mul_mm_manual`, with `const short vsg = tiitg / 32;`
for wave64. The fork's `0006`/`0007` are the same branch plus an `NLR == 8` variant,
narrow/wide tiles, double buffering, `acc_f32`/`uniform_scale`, and a separate
`kernels/mul_mm_w64.metal` compile unit.

Its published numbers are not quotable: no harness, no N, no warmup policy, no raw
logs, and its `HOWTORUN.md` documents `llama-bench` as broken for 12B models. Its
13x/12x table multiplies in `--no-mmap` residency and attributes only 2-2.9x to
wave64 decode, with no isolated measurement.

### Genuinely actionable from it

1. **Command-buffer node budget.** It GPU-faults when one command buffer carries too
   much of a large wave64 graph ("command buffer status 5, e00002bd Internal Error"),
   and splits at an empirical ~75 nodes per buffer with `MAX_COMMAND_BUFFERS` 64.
   This fork serialises discrete GPUs but keeps `#define GGML_METAL_MAX_COMMAND_BUFFERS 8`
   and no per-graph node budget. Unverified here, worth a look before any large-model
   wave64 work.
2. **9-character tool-call-id fix.** Confirmed absent locally:
   `tools/server/server-common.cpp:111` is still `std::string random_string()` and
   `common/chat.cpp:253` is still `if (!tool_call.id.empty())`. External assigns the id
   unconditionally. Fixes turn-2 breakage with templates that validate ids.
3. **Its divergence-finding harnesses** (`EVCB_STATS`/`EVCB_RAWDUMP` in
   `examples/eval-callback`, `TBO_ELEMDUMP` in `tests/test-backend-ops`) answer "which
   is the first genuinely divergent op between config A and B" with one env var, and
   include an index-mod-32/64 histogram that exposes lane and tail bugs. That is a
   sharper instrument than anything here for the class of bug this fork fights.
4. **A narrower concurrency gate**: it serialises only wave64 *decode*, where this fork
   serialises every discrete GPU. Only safe behind a per-op correctness gate.
5. **An unverified coverage question**: it instantiates the FA vec kernel for DK
   128/256/512 across nine K/V type pairs including asymmetric mixes. Whether
   `kernels/fa.metal` here covers the same matrix was not checked. If it does not, that
   is a real gap on exactly the quantized and asymmetric cases.

### fa.metal coverage: no gaps, and the check that was proposed cannot detect them

Measured from the shipping artefact, `vendor/llama.cpp/build-static/bin/kernels/fa.metallib`:

- **12 DK widths**: 40, 64, 72, 80, 128, 160, 256, 320, 384, 512, 576, 640
- **24 K/V type pairs**: {f16, q4_0, q8_0, turbo2, turbo3, turbo4} x the same six
- **6 dispatch variants** per pair: bare, `_w64`, `_w64_lds32`, `_w64_wg32`, `_w64_wg32_lds32`, `_wg32`
- 861 distinct names, 1722 symbol lines (fat binary, one per architecture)

The external branch declares DK {128, 256, 512} x 9 pairs = 27 instantiations. This fork
covers 12x the DK widths and 2.7x the pair count, and includes asymmetric and non-power-
of-two widths (40, 72, 80, 160, 320, 384, 576, 640) that the external does not enumerate.
**There are no gaps to document against its matrix; the fork is the superset.** Recording
"known limitations" here would have been backwards.

`tools/check-fa-amd-kernels.sh` verifies the three names a GCN fallback would request.
Two traps it documents, both of which bit while writing it:

1. `strings FILE | grep -q NAME` under `set -o pipefail` reports failure **on a match**.
   `strings` dies of SIGPIPE when grep exits before draining the pipe, pipefail turns the
   141 into a non-zero pipeline, and every present kernel reads as ABSENT. The same trap
   reported exit 141 earlier in this session and was misread then as a crash. The check now
   materialises the symbol list once and uses here-strings, with no pipe in the path.
2. **Presence is not usability.** All three names are present, and
   `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64` is the exact pipeline that fails
   `newComputePipelineStateWithFunction` at runtime with `GPGPU, exceed the local data
   storage limit`. A presence check green-lights the broken kernel. The script therefore
   exits 0 on presence but says so in the output, and takes `FA_AMD_PROBE=` to test pipeline
   creation, which is the only evidence that matters.

### Upstream sync (ticket 31): nothing to port, because upstream has no engine

`upstream` is `engeldlgado/toshllm`. `git fetch upstream` puts `upstream/main` at
`523b814 release: 0.87.26`, 44 commits ahead of local HEAD and 72 behind it.

The 44 commits are all application-layer: MCP transports, extension agents, MapLibre maps,
Russian localisation, PMTiles byte-range serving, HELPERS.sha256. Measured on the trees:

```
files matching ggml-metal in upstream/main:  0
files matching ggml-metal in HEAD:           0
top-level vendor entries upstream:           0
```

Upstream carries no llama.cpp source at all, so step 2 as written has no subject: there is
no metal, amd, wave64 or gcn path to diff, and no upstream kernel changes to port into
`patches/llama/metal/`. The engine lives in the `vendor/llama.cpp` submodule, which is not
in either index, and the fork's engine work is carried as `patches/`. Reconciling the two
repositories is an app-layer question (0.87.24-beta.1 here against 0.87.26 there), not a
metal one.
