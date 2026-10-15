# Firellama max-perf map

## Destination

Firellama runs the biggest models this Mac Pro can hold at the fastest tok/s it can sustain — both D700s engaged under a split VRAM budget backed by 64GB RAM — with the Metal timestep defect fixed, the external-server expose fixed, every claim measured locally, and everything pushed to `firellama-v0.87.11`.

## Notes

- Glossary: `CONTEXT.md` (split budget / per-device ceiling / per-buffer ceiling, thread rule, pp-vs-tg). Use its terms in every ticket answer.
- Prior spec: `.scratch/firellama-dual-gpu/spec.md` (measure-first baseline, still valid).
- Measured baselines: `docs/bench-baseline-2026-09-30.md`, `docs/thread-sweep-2026-09-30.md`, `docs/server-check-14b-2026-09-30.md`, `docs/avx1-result-2026-09-30.md`.
- Patch rules: `patches/README.md` — numeric order, never reuse a number, one patch per change, `-U8`, round-trip check. Next number is 0114 (reserved for the timestep fix; see Q4 below).
- Tight loop before theory (diagnosing-bugs skill): one command, red-capable, deterministic, fast, agent-runnable.
- Fork issues are disabled, so this map lives local. If fork issues get enabled, graduate it to a native `wayfinder:map` issue.

## Decisions so far

- Three-ceiling vocabulary adopted; bare "12GB VRAM" retired.
- Acceptance models are Qwen3-14B-Q4_K_M and Ternary-Bonsai-27B; 35B-class stays fog.
- Usage-issue scope is peer default, device-env contract, fit-abort warning, MoE split-budget sizing.
- Timestep fix comes before perf work; restarted from sentinel semantics after the `precise::` theory failed (build never ran, error non-deterministic across runs).
- External-server defect is binds-localhost-only (Q6 answer).
- **Timestep defect resolved (2026-10-01).** GCN miscompiles `args.dim % 2 != 0` and takes
  the odd-dim branch for an even `dim`, so every row zeroed its successor's first element and
  the last row wrote past the end of `dst`. Fix: `half_ * 2 < args.dim`, patch 0114,
  kernel-local so no pp/tg baseline was owed. Full suite 10701/10701, was 1 failure.
- **Sentinel mismatch reading**: a sentinel mismatch means a write landed outside its tensor;
  the ERR magnitude alone did not localise it. Byte-level probing in the test harness found it
  in one run. Do not theorise from the error value.
- **External-server defect resolved (2026-10-01).** The menu-bar per-server toggle wrote
  `profile.localNetworkDiscovery` without pinning `Profile.Pin.discovery`; an added server
  always has a pinned list, so `effectiveSettings()` dropped the value and emitted
  `--host 127.0.0.1`. Getter had the same gap, so the switch read on. Fixed in
  `ToshLLMApp.swift`. LAN curl proof still owed (needs a second machine and a working build).
- **Fit-abort fixed (2026-10-01).** The engine already logged the abort; the app never surfaced
  it. Now a `fitNote` on the server card.
- **Q1 (2026-10-01): 27B acceptance runs first, in background.** Ticket 08 is unblocked, needs a free machine, and takes hours; ticket 06's planner sizing depends on its numbers and not on any kernel fix. Sequence: claim 08 and start the run, do the timestep red loop (01) while it runs. Ticket 08 still requires the machine free, so only one long run at a time.
- **Q2 (2026-10-01): ticket 02's bench gate splits by blast radius.** A kernel-local fix to `kernel_timestep_embedding_f32` cannot regress the text path (diffusion/image only), so it gates on full `test-backend-ops` green plus a smoke bench. Only a shared-helper change owes the full 4B tensor-events baseline (153.3/17.5). The gate must name which case applied.
- **Q3 (2026-10-01): research tickets resolve at findings, not at landed fixes.** Ticket 07 is research-only (drop point file:line + proposed fix). New ticket 09 carries the fix and the LAN curl proof, blocked by 07. The local tracker has no separate implement ticket, so splitting is the way to stop research sprawling into implementation.
- **Q4 (2026-10-01): `patches/llama/0114-metal-timestep-embedding-precise.patch` deleted.** An uncompiled, theory-only patch sitting in the applied series risks entering a build that greps by number. Its content is preserved in ticket 02. Number 0114 stays reserved for the real fix; never reused for anything else.

## Not yet specified

- 35B-class MoE on split budget + 64GB RAM (ticketable after 27B passes).
- Whisper / stable-diffusion engines under split budget (phase 2; llama engine + app first).
- Precompiled `default.metallib` (143s first-load shader compile is annoying, not blocking).
  **Blocked on this machine**: `xcodebuild -downloadComponent MetalToolchain` requires an Xcode
  app and there is none; `softwareupdate` does not offer the toolchain. Needs a machine with
  Xcode to build a DMG that has them.
- Per-buffer 3.5GB ceiling workarounds if a real model hits the `:1154` abort.

## Out of scope

- Upstream PRs to llama.cpp / ToshLLM (private fork only).
- CUDA, ROCm, Vulkan, Apple-silicon tuning, mixed-GPU configs.
- Reimplementing Dynamic MoE or the GCN concat fix (inherited from v0.87.11).
- UI redesign, translations, or changes without a bench number behind them.
- Whisper/SD kernel work (phase-2 fog).

## Tickets

| # | ticket | type | status | blocked by |
| --- | --- | --- | --- | --- |
| 01 | Timestep red loop | task | resolved | — |
| 02 | Timestep correct fix as 0114 | task | resolved | 01 |
| 03 | mgpuPeer default | task | resolved — gated on peerGroups | — |
| 04 | Device-env contract | task | resolved — premise refuted | — |
| 05 | Fit-abort warning | task | resolved | — |
| 06 | MoE split-budget sizing | task | resolved — planner dormant, latent one-card read | 08 |
| 07 | External server host | research | resolved | — |
| 08 | 27B acceptance run | task | resolved — 11.54 pp512 / 6.22 tg64 | — |
| 09 | External server LAN fix | task | code landed, runtime proof owed | 07 |
| 10 | Events + layer split deadlock | bug | resolved — app gate + engine fix in 0115 | found by 08 |
| 11 | Engine xdev stall, NSRange, split assert | bug | resolved (split assert diagnosed, not fixed) | 10 |
| 12 | Ship hardening: LAN proof, memset test, CI probe | bug + test | resolved except notarization and Metal toolchain | release |
| 13 | Tensor split on an undividable model | bug | resolved — exit 86, app retries by layers | user report |

## Blocked

- ~~The app does not compile on this machine.~~ **Cleared 2026-10-02 (beta.2).** Both errors are
  fixed: `VideoGenTab` returns `[Data]` via `displayFrameData(_:)` and builds the image on the main
  actor; `ChatTab` and `DesignSystem/Views.swift` put `sharedBackgroundVisibility` and
  `ToolbarSpacer` behind `#if compiler(>=6.2)`, which resolves the symbol problem without needing a
  real 26 SDK. `swift build` is green and the beta.2 bundle is installed and measured.
- The 27B `qwen35` SSM state reshape cannot be tensor-split at all: `ne[0]=6144` does not
  divide `ne[0]=9216`. That limit stands and layers are the model's only option. What changed
  is how it is reported: the engine exits 86 naming the op and dimensions, and the app retries
  once with layers by itself (ticket 13). Marking the tensor unsplittable would hand the
  scheduler a split state that does not describe the data, so the failure stays loud.
- **Ticket 09's LAN proof is closed (2026-10-03).** Verified from a second physical machine by the
  owner. The earlier same-host second-IP check stands as the local record.
- **Notarization is deferred by decision (2026-10-03),** to the point the project is rebranded. The
  pipeline in `build.yml` is wired and skips cleanly; adding the credentials is all that remains.
- Precompiled Metal kernels are no longer blocked (2026-10-03): Xcode 26.3 and the Metal
  toolchain are installed on this machine, first launch is 16 s against 143 s, shipped in
  beta.3.
- **Meta-backend tensor split measured against the layer split, 2026-10-15.** Qwen3-14B-Q4_K_M,
  -ngl 99 -c 16384 -t 10, both D700s, seed 42 temp 0, TOSH_MGPU_TRACE=1 + XDEV_COUNT=1.
  Parity PASSES: identical 20 token IDs on "The capital of France is" for both split modes.
  Throughput: tensor 8.40 tok/s decode vs layer 5.12. Parity held across four runs.
  RETRACTED: an earlier entry here read the 1.64x gap as "tensor beats layer", and derived an
  18% collective cost and 133 us per exchange from it. Both are void. Per-card work is identical
  in the two modes (layer split 20 full layers, tensor split 40 layers at half width), so the gap
  is not a collective measurement at all: a layer split is sequential by construction and a
  single-token decode gives it nothing to overlap. bench-baseline 2026-09-30 line 6 vs 11 shows
  Qwen3-4B-Q6_K at 12.00 tok/s single card and 11.96 on layer dual, i.e. 0.997x. The second card
  contributes no concurrency. Collective cost is NOT MEASURED.
  Also retracted: TOSH_MGPU_NOWAIT=1 was used as a control and returned an identical 8.40, which
  was read as "the wait costs nothing". The flag is inert on this path. Its only call sites are the
  peer-fused, peer-push and one-shot paths; the staged host-block path taken by decode on an
  unbridged pair consults only TOSH_MGPU_WAIT_SATISFIED and TOSH_MGPU_BP_SATISFIED
  (ggml-metal-context.m 3891-3898, 3939-3947). It was a null experiment, not a null result.
  SETTLED: the exchange count. AllReduce fires only at GGML_BACKEND_SPLIT_AXIS_PARTIAL
  (ggml-backend-meta.cpp 2539-2546, one per subgraph cut, 2866-2877), which requires both mul_mat
  sources axis-0 split; for a dense transformer that is attn_output.weight and ffn_down.weight only
  (llama-model.cpp 543, 584). Two collectives per layer is the design, matching Megatron TP. The
  trace's 160.01 per token per card over 40 layers is those two seen as four directed exchanges,
  since one AllReduce at TP2 issues two directed exchanges (ggml-metal.cpp 1486-1493). No surplus.
  First pass ran with a KeepAlive launchd agent (com.user.llama-server, -ngl 0, 12 threads) alive.
  Re-ran with it unloaded: layer 5.02 -> 5.12, tensor 8.49 -> 8.40, within noise.
  WIDENED PARITY 2026-10-15: 256 greedy tokens on a fixed prefix, one card-pair, sequential model
  loads. Token IDs identical, text identical. Chosen-token logprobs max abs delta 1.96e-03, mean
  1.53e-04, 166 of 256 positions above 1e-6. That is float summation order, not a results
  difference. N=1 per mode, no warmup discarded. This build returns logprobs as
  completion_probabilities, not logprobs.chosen_token_logprob.
  Q3 CLOSED: 0038 is a correctness fallback only. It converts exactly one GGML_ABORT into exit 86
  when a tensor's per-device slice width does not divide its full width times its repeat ratio
  (ggml-backend-meta.cpp 1227-1256). No branch anywhere measures speed or memory. The app relaunches
  once by layers on exit 86 (Server.swift 2093-2102) and pre-downgrades on an expert-scale tensor
  (Server.swift 1269-1272). Note it converted only that one abort; sibling aborts at 741, 787, 1205,
  1269 still kill the process.
  ISA: host is Ivy Bridge-E (Xeon E5-2697 v2), 22nm, 12c/24t at 2.7 GHz, 30 MB L3, DDR3-1866.
  Confirmed by feature bits, not brand string: machdep.cpu.features tops out at AVX1.0 RDRAND F16C,
  leaf7_features carries no ISA extensions. No AVX2, no FMA3, so TOSH_NO_AVX2=1 is required.
  Note build-engines.sh defaults to AVX2+FMA+BMI2 when neither knob is set, which SIGILLs here.
- **Upstream 0.87.24 merged 2026-10-15** (0.87.24-beta.1). Extensions framework (tools,
  agents and settings from folders, off until approved), maps in chat from Apple Maps, Ukrainian
  translation, a remote MCP server reachable through a local relay, and make-app.sh able to
  package another product. Pin and patch numbering unchanged, so ours kept 0035-0038.
  `patches/llama/metal/0013-vram-budget-and-private-mirror.patch` could not apply (placeholder index
  hashes) and collided with `quant/0013-turbo-kv.patch`, so it was removed and the series failed at
  position 14 until then. It arrived with 7b05cc1 on `origin/phase1-metal-d700-optimization`
  (2026-10-14) — the sibling commit 2650d68 there added `-DGGML_METAL_MGPU=ON`, now removed as
  inert (nothing in the tree reads it). Not in any release: beta.1 verified on 10-12, two days
  before 7b05cc1 landed. The private-mirror work itself was never real: zero read sites.
- **Upstream 0.87.19-0.87.23 merged 2026-10-12** (0.87.23-beta.1). Pin stayed at d8123504938
  and upstream added no patch numbers, so ours held 0035-0038 and none needed regenerating — the
  first no-op merge for our patches since 0.87.16. Upstream rewrote its own 0013, 0022, 0029, 0030.
  Gates: test-backend-ops 11682/11682 on MTL0, test-metal-memset all checks passed, swift test
  396 tests 15 skipped 0 failures, SymPy engine integration 14 tests 1 skipped 0 failures.
- **Upstream 0.87.16/17/18 merged 2026-10-08** (0.87.18-beta.1). llama.cpp pin moved
  9575389609d6 -> d8123504938 (v0.6.0) and upstream regrouped the series into area folders
  (core/metal/mgpu/model/moe/quant/server/spec), so ours moved to 0035-0038 and the series is
  38 patches. 0037 and 0038 regenerated; logic unchanged. Gates: test-backend-ops 11682/11682 on
  MTL0, test-metal-memset all checks passed, swift test 393 tests 15 skipped 0 failures, SymPy
  engine integration 14 tests 1 skipped 0 failures.
- **Upstream 0.87.15 merged 2026-10-03** (0.87.15-beta.5). Math answers come from one agent in the
  engine, for the chat, the web chat and API clients. Upstream took patch 0127, so ours moved to
  0128-0131; the series is 126 patches. Gates: test-backend-ops 10721/10721 on MTL0,
  test-metal-memset all checks passed, swift test 371 tests 15 skipped 0 failures, SymPy engine
  integration 14 tests 1 skipped 0 failures.
- **Upstream 0.87.14 merged 2026-10-03.** SymPy and NumPy math tools, math-call guards, Flash-Next
  64-lane speedups. It took patch numbers 0125 and 0126, so ours moved to 0127-0130; the series is
  125 patches. Gates after the merge: test-backend-ops 10721/10721 on MTL0, test-metal-memset all
  checks passed, swift test 345 tests 10 skipped 0 failures, and the 9 SymPy engine integration
  tests pass with TOSH_SYMPY_E2E_MODEL set.
- **arm64 is out of scope by decision (2026-10-03).** The fork targets Intel x86_64 only. The
  `ARCH=universal` / `TOSH_ARCH=universal` machinery stays in the scripts, unused.
- **The `NSMakeRange` A/B is closed (2026-10-03).** `test-metal-memset` gained the DSV4 shape:
  one KV tensor, 8 streams of 512 bytes, cleared one at a time at `n*stream_size`. Fixed engine:
  0 streams damaged. Reverted engine: stream 1's overfill takes stream 2 with it, 4 checks fail.
  Not run with a real DSV4 model — the smallest is 82.5 GB and the mechanism is already pinned at
  one call site with a deterministic reproducer. Details in `docs/agents/apple-silicon-handoff.md`
  T5.

See `docs/agents/apple-silicon-handoff.md` for the full open-work list and the gates.

