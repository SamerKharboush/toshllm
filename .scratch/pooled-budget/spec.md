# Spec: the pooled budget levers for 0.87.27-beta.3

Status: ready to hand off, revision 2 (2026-10-25). Revision 1 was 2026-10-24. Map: `map.md`. Glossary: `CONTEXT.md`
(**pooled budget**, **display card**, **expert tier**).

Every build ticket below is implemented by OpenCode from a brief. The orchestrator reviews
each diff, re-runs the gates, makes the patch, and commits. Patch numbers continue the global
series: 0048 is next.

## What is known (the rows every gate compares against)

All rows use the fork engine `d81235049` plus the patch series, built AVX1. The model is
Ornith-1.0-35B Q6_K with the app's launch: `-c 16384 -fa auto --load-mode none --cache-ram
2048 --cache-reuse 256 --parallel 1`, `TOSH_FA_AMD=1`. Compare rows only within one session:
card 1's decode drifted from 13.13 to 12.87 tok/s between 2026-10-22 and 2026-10-23.

| row | decode (tok/s) | prompt, 2402 tok (tok/s) | source |
|---|---|---|---|
| host `-ngl 0` | 11.2–11.9 | 27.5 | thread sweep, 2026-10-22 |
| expert tier, card 1 | 12.8712 (sd 0.0364, N = 18) | 73.3144 | card A/B, 2026-10-23 |
| expert tier, card 0 (display asleep) | 12.7829 (sd 0.0240, N = 18) | 73.1617 | card A/B, 2026-10-23 |

A decode token on the expert tier takes about 78 ms:
- **The CPU experts take about 16 ms**, and every ms of their time is on the critical path:
  slope 0.976 against host time (ticket 01).
- **Bytes:** about 221 experts per token go to the CPU, about 2.58 MB each at Q6_K. That is
  roughly 570 MB per token, or about 35.8 GB/s during the 16 ms. This is an estimate from the
  measured job counts and the quant size; this machine's sustained bandwidth is not measured.
  The theoretical peak is 59.7 GB/s (4 × DDR3-1866).
- **The rest is GPU kernel time** (ticket 09, measured with 0048, 1182 tokens): the GPU has
  command buffers running for 73.4 of the 76.0 ms. The CPU experts' 14.4 ms are waits inside
  that span (from ticket 01's slope). That leaves about **59 ms of GPU work**, the largest
  share. Host encode is 6.6 ms and mostly overlaps the GPU; 2.6 ms has no GPU work.

## Ranked work

### 1. Measure the 62 ms (map ticket 09). Patch 0048, then a run. DONE 2026-10-25.

Answered: about 59 ms of GPU kernel work, 14.4 ms of CPU-expert waits inside it, and 2.6 ms
with no GPU work. The patch is in the series with its clock and kind-24 fixes. The original
plan follows.

- **Build:** four diagnostic timeline kinds behind `TOSH_DMOE_TIMELINE`, with no behaviour
  change when it is unset:
  - 20: a CPU expert job;
  - 21: GPU span of each graph command buffer;
  - 22: host time in `ggml_metal_graph_compute`;
  - 24: one `llama_decode` call.
- **Run:** one server on card 1, 1 warmup + 3 measured 200-token decodes, and the
  decomposition per decode token:
  - wall time (kind 24);
  - GPU span (the union of the kind-21 spans in that wall);
  - CPU expert time (the sum of kind 20);
  - host encode time (kind 22);
  - wall minus GPU span, the time the GPU had no work.
- **Gates:**
  - built clean, 0 AVX2/FMA mnemonics;
  - with the timeline unset, decode within the noise of the expert-tier row in the same
    session;
  - the timeline holds every kind it should.
- **Decides:** whether one card has anything past the about 16.1 tok/s bound of the CPU
  levers. If the GPU span is mostly the waits on host jobs, then the GPU side (attention plus
  resident experts) is the next lever and gets its own ticket.

### 1b. Which GPU ops take the 59 ms (map ticket 10), a diagnostic patch

- **Build:** a diagnostic mode (an env variable) that commits each op, or each op kind, in its
  own command buffer and records its GPU span. Nothing changes when it is unset.
- **Run:** card 1, the same launch. Report:
  - per op kind: count, GPU ms per token, and the share of the 59 ms;
  - the per-op mode's own token time next to the normal one, since its overhead must be
    visible;
  - the join op's span, which measures the host wait directly.
- **Decides:** whether GCN kernel work, for example the Q6_K/Q4_K matmul-vec or the delta-net
  ops, becomes the top lever. It would help every model on the cards: the dense 8B decodes
  at only 9.0 tok/s across both (R25). If it does, it gets its own ranked item ahead of 3,
  and the user is asked to re-confirm the order.

### 2. The two-card expert tier (ticket 71, shape decided in map ticket 07)

Layer-split arenas: each card holds the attention, KV and hot-expert arena of its own layers.
One host executor serves both. 8 KiB per token crosses at the layer boundary.

What it is for, stated before it is built: **capacity**. It puts both cards' VRAM to use,
allows longer contexts, and runs MoE models whose non-expert weights plus KV do not fit one
card. Its decode gain on the 35B is expected to be small: the arena's hit rate rises slowly,
and each host expert costs about 64 µs. Its gate protects decode; it does not promise a
speedup.

The work comes in three briefs, in order. Each one is a separate patch or commit.

- **2a. Planner, patch 0050.** Under `GGML_METAL_DEVICES=2 --split-mode layer` with
  `--dynamic-moe on`, the planner budgets each device:
  - each device's free VRAM;
  - the layers the split gives it;
  - an arena and prefill slots per device.

  `TOSH_AUTO_DRY_RUN=exit` shows both. Today's single-device query is at
  `common/tosh-plan.cpp:355-372`.
  - Gate 1: on the 35B at `-c 16384`, the dry-run JSON lists two device budgets, each within
    its device's free VRAM.
  - Gate 2: the one-card dry-run JSON is byte-identical to today's for the same arguments.
- **2b. Runtime, patches 0051-0053** (design:
  `design/two-card-runtime-analysis-2026-10-25.md`). 0051 is per-device plumbing with no
  one-card change. 0052 is per-device arenas and budget. 0053 is the executor polling every
  card's event and signalling the layer's card, the policy's per-device uploaders and
  observation rings, and the bank planner. The original plan follows.
   Replace the single arena (`g_arena_buf`, one GPU from
  `ggml_backend_dev_by_type(GPU)` at `src/llama-tosh-dmoe.cpp:1865-1869`) with one arena
  buffer per device. Each layer's arena is allocated on the device that holds that layer's
  weights, and the executor stays one. The Metal rendezvous state is already per device
  (`ggml-metal-device.m:1225-1232`). Show that the single publish sequence holds when the two
  cards run one after the other within a token; do not assume it.
  - Gate 1: the 35B at `-c 16384` across both cards, with the log showing mixed execution and
    an arena on each device.
  - Gate 2: 0 degenerate answers, opening like the host.
  - Gate 3: N ≥ 6 measured, alternating with the one-card expert tier in the same session.
  - Gate 4: the one-card path unchanged (its row within noise).
  - Gate 5: the cross-card bytes per token stated.
  - Also: one cell at a context one card refuses.
- **2c. App.** On the D700 pair, a MoE model that does not fit takes the two-card expert
  tier: `GGML_METAL_DEVICES=2 --split-mode layer --dynamic-moe on`, with no `--n-cpu-moe`,
  no ubatch and no draft. If the two-card plan is refused it falls back to the one-card
  tier, and then to the host.
  - Gate: `swift build`, and `swift test` with no new failures beyond the
    `MCPStdioTransportTests` race. The tests assert the launch flags and the environment.

### 3. The AVX1 expert kernel (lever (a))

**3a is done (2026-10-25):** the read-only bandwidth sustained at 12 threads is 51.6 GB/s.
The CPU experts already stream an estimated 35.8 GB/s. So a perfect AVX1 kernel saves at most
about 5 ms per token on the 35B (an estimate). Lever (a) stays open, but bounded.

- **3a. Task: measure the bandwidth this Xeon sustains.** Use a STREAM-style triad over 12
  threads with 1 GB arrays, built AVX1 (`-mavx -mno-avx2 -mno-fma`). Repeat it 5 times; give
  mean and sd.
  - This bounds the kernel: if sustained bandwidth is near the experts' estimated 35.8 GB/s,
    the kernel is memory-bound and lever (a) closes.
- **3b. Build, only if 3a leaves room:** the gate/up path of the host executor (`job()` in
  `src/llama-tosh-dmoe.cpp`; per job: quantize, gate/up, down).
  - Gates: the host time per job falls beyond the noise, decode rises in the same session,
    0 AVX2/FMA mnemonics, 0 degenerate answers.

### 4. Overlap at the join (lever (c))

Fog until 1 and 3 report. It needs a design change at the join, and its ceiling is the same
16 ms.

## Not in this spec

- **Dense models bigger than VRAM.** A draft was measured slower (ticket 08), and no lever is
  left. A Qwen3.5 0.8B draft would need a download.
- **The slow mode** (ticket 72): open, and only seen with the display awake. Re-test with
  `caffeinate -d` and an animation on screen; that needs the user at the screen.
- Soup, bridging the cards, and per-token model streaming (out of scope on the map).

## Release

When 1, 2 and 3a are in, the beta.3 record follows the beta.2 pattern:
- VERSION, CHANGELOG and README rows;
- assert_artifact, preflight and the DMG digest;
- push with `git push origin phase1-metal-d700-optimization`, only when the user says so.
