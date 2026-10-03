# Firellama — session summary (2026-09-29 → 2026-10-01)

## 1. Goal

Make ToshLLM fast on this machine; publish the work so others with the same hardware benefit.

Destination (grilling Q1–Q5, all accepted): Firellama runs the biggest models this Mac Pro can hold at the fastest tok/s it can sustain — both D700s engaged under a split VRAM budget backed by 64GB RAM — with the Metal timestep defect fixed, the external-server expose fixed, every claim measured locally, everything pushed to firellama-v0.87.11.

## 2. Hardware (measured)

| Property | Value |
| --- | --- |
| CPU | Xeon E5-2697 v2, 12c/24t, AVX, no AVX2, no FMA/BMI2 |
| GPU | 2x FirePro D700 (Tahiti, GCN 1.0, 0x6798), 6GB each, PCIe x16 |
| Metal | Metal 2, MTLGPUFamilyCommon3, no simdgroup reduction/matrix mul |
| GPU link | none — "peer group 0, not bridged" |
| maxBufferLength | 3.5 GiB per card |
| RAM / OS | 64GB / macOS 15.8 (24H23) via OCLP 2.5.1 |
| Toolchain | no Xcode (no Metal compiler), cmake hand-installed |

## 3. Repo rules

- ~/firellama, origin SamerKharboush/toshllm, upstream engeldlgado/toshllm, branch firellama-v0.87.11, base b2199a3, GPL-3.0.
- vendor/llama.cpp pinned at 9575389609d6…; patches/llama/*.patch rebuilds it. build-engines.sh resets the vendor tree and reapplies the series every build (lines 157–164) — vendor-tree edits are temporary, must become a patch.
- Patch rules: numeric order, never reuse a number, one change per patch, -U8, round-trip check. Series runs 0001–0113; next is 0114+.
- iRon-Llama-RC1 has no license — nothing copied from it.
- Fork issues disabled → specs/map/tickets live in .scratch/.

## 4. The ISA trap

Default build emitted -mavx2 -mfma -mbmi2; Ivy Bridge has AVX only → EXIT=132 (SIGILL) before model load. Upstream ships a noavx2.dmg for this reason.

Two knobs in scripts/build-engines.sh: TOSH_NO_AVX2=1 (SSE4.2-only) and TOSH_AVX1=1 (ours: SSE4.2+AVX+F16C, AVX2/FMA/BMI2 off). Smoke after TOSH_NO_AVX2=1: EXIT=0, 0.6B pp64 368.72 / tg32 51.06.

AVX1 measured: no delta (141.72/17.43 vs 141.71/17.50). Prefill is GPU matmul; decode is BLAS-bound at these sizes. Kept as the correct flag set.

## 5. Baselines (Qwen3, 12 threads)

| model | mode | pp | tg |
| --- | --- | --- | --- |
| 0.6B-Q8_0 | single | 368.72 | 51.06 |
| 4B-Q6_K | single | 78.70 | 12.00 |
| 4B-Q6_K | tensor, none | 141.71 | 17.50 |
| 4B-Q6_K | tensor, peer | 141.85 | 17.49 |
| 4B-Q6_K | tensor, events | 153.26 | 17.48 |
| 4B-Q6_K | layer, 2 GPUs | 78.45 | 11.96 |
| 14B-Q4_K_M | layer, 2 GPUs | 29.24 | 5.10 |
| 14B-Q4_K_M | tensor, server, long prompt | 40.48 | 7.95 |

- Tensor = speed path (+95% pp, +46% tg vs single). Events best prefill (+8%); peer inert (not bridged). tg flat across sync configs.
- Layer = fit path: no gain at 4B; its value is that 8.38GB 14B loads across 2×6GB with no :1154 abort.
- Coherence verified across all sync configs on 4B and 14B.

Threads: 12 → 153.13/17.41 · 16 → 153.26/17.24 · 24 → 152.13/11.72 (decode collapses, SMT contention).

Env contract: tensor opens both GPUs with DEVICE_LIST=0,1; layer ignores DEVICE_LIST and needs GGML_METAL_DEVICES=2. mgpu-report.sh's layer section passes no --split-mode, which is why it reports single-GPU rows.

## 6. Shipped (4 commits, pushed)

451e67c threads→physical · 5a3d5eb TOSH_AVX1 knob · 09d1f12 baseline docs · base b2199a3.

### 6.1 Threads (the one real win)

SettingsTab.swift default 6→0(auto), Stepper cap logical→physical; Server.swift new resolvedThreads(_:) returning physical when 0/unset, clamping otherwise.

## 7. Open defect — TIMESTEP_EMBEDDING fails on GCN

ERR = 0.003125032 > 0.000000100 sentinel mismatch: sent_2   → FAIL
Everything else passes. Diffusion/image path only; LLM text path coherent.

Mechanism (read from source): sentinels are f32×1024 injected after every tensor and memcmp'd GPU-vs-CPU (test-backend-ops.cpp:1291-1318, 1490-1502). A mismatch means memory differs — OOB write/aliasing/uninit — not a numeric verdict on the kernel output. Output shape [dim=320, ne0=2] can't overflow (ggml.c:5512). The value drifts run-to-run (3.125e-3 → 3.1109e-3), which deterministic fast-math error would not do.

What I got wrong: I hypothesized GCN fast-math precision loss, cited precise::tanh precedent, patched the vendor tree, and generated 0114-metal-timestep-embedding-precise.patch (27 lines, 4 changes). That build never ran — /tmp/build-kernelfix.log didn't exist, and the FAIL I quoted afterwards was the pre-fix binary. The patch is unverified and probably wrong. Do not reuse number 0114 for anything else; ticket 02 decides rewrite vs delete.

Correct next step: build the tight red loop first (one command, filtered to TIMESTEP_EMBEDDING, seconds, deterministic), then hypotheses → instrument → fix.

## 8. Usage issues in scope (each needs measured before/after)

peer default true but inert here; device-env contract (verify the app exports the right var, make silent single-GPU loud); --fit silently aborts under -ngl 99 preset; AutoMemoryPlan may size against one card rather than the split budget.

## 9. External server — binds localhost only (Q6)

Expose ignores the external-host setting; answers on 127.0.0.1, LAN refused. Untraced — ticket 07.

## 10. Glossary

"12GB VRAM" retired. Canonical: split budget (~12GB) under layer split · per-device ceiling (6GB) · per-buffer ceiling (3.5GB). Acceptance models: 14B-Q4_K_M and Ternary-Bonsai-27B-PQ2_0; 35B-class stays fog.

## 11. Map (.scratch/firellama-maxperf/)

| # | ticket | type | blocked |
| --- | --- | --- | --- |
| 01 | Timestep red loop | task | — |
| 02 | Timestep correct fix as 0114 | task | 01 |
| 03 | mgpuPeer default | task | — |
| 04 | Device-env contract | task | — |
| 05 | Fit-abort warning | task | — |
| 06 | MoE split-budget sizing | task | — |
| 07 | External server host | research | — |
| 08 | 27B acceptance run | task | — |

Fog: 35B-class; whisper/SD under split budget (phase 2); precompiled default.metallib (143s first-load shader compile); per-buffer 3.5GB workarounds. Out of scope: upstream PRs; CUDA/ROCm/Vulkan; Apple silicon; mixed-GPU; reimplementing Dynamic MoE or the GCN concat fix; UI redesign.

## 12. Blocker

The active model (oc/space-bunny-free) also hosts the Bash safety classifier. While that endpoint is unavailable, Bash, Write, Agent, WebSearch all fail; only Read works. Builds/benches must run via your ! prefix, or switch to a claude-* model to restore the classifier and I'll run everything myself.

In flight:

```
! export PATH="/Applications/CMake.app/Contents/bin:$PATH" && cd ~/firellama && TOSH_AVX1=1 nohup ./scripts/build-engines.sh > /tmp/build-kernelfix.log 2>&1 &
```

Then: `! grep -a 0114 /tmp/build-kernelfix.log` must show the patch applied, followed by the filtered test-backend-ops run. Honest expectation: the precise:: patch may not turn this green. A red result is a valid outcome and feeds ticket 01.
