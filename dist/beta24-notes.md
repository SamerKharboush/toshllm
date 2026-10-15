# ToshLLM 0.87.24-beta.1

Upstream 0.87.24 merged. The 0.87.23-beta.1 fork release stays as its own release.

## What is new

- **Extensions framework.** Tools, agents and settings pages come from extension folders in a
  documented format. The app's own extensions and the ones in a folder you pick stay off until you
  approve them.
- **Integrations.** A build can bundle MCP servers, an agent and their settings for the engine,
  shown in Settings as Integrations, with secrets kept in the Keychain and handed to the engine only
  through its environment.
- **Maps in chat.** The model can draw places, routes and areas on a map, dashed and marked as
  approximate, and a road route from Apple Maps once you allow the internet. The maps an agent
  returns stay as they are.
- **Tool cards** show the call's operation, a readable summary and laid-out JSON, and an extension's
  agent can hand a turn back to the chat's own tools.
- **A remote MCP server** approved for the server agent, or bundled as an extension, reaches the
  engine through a local relay over Streamable HTTP or HTTP+SSE, with its headers kept out of the
  command line.
- **Ukrainian translation** added, completing 100% of the 88 strings of extensions, the math tools
  and the tool cards. Italian, Japanese and Chinese updated.
- **make-app.sh can package another product** from this tree with its own name, bundle id, data
  folder, version, icon and no in-app updates. ToshLLM's identity stays the default, so these builds
  are unaffected.

## One build change rides along

This release was built from `phase1-metal-d700-optimization`, which carries 2650d68: the engine
build now passes `-DGGML_METAL_MGPU=ON`. That flag was not in 0.87.23-beta.1. It is what the
build I measured and packaged was compiled with, and the full gates passed on it, so the release
carries it rather than silently reverting it.

## A patch that cannot apply was removed

`patches/llama/metal/0013-vram-budget-and-private-mirror.patch` carried the same number as
`patches/llama/quant/0013-turbo-kv.patch` and carried placeholder index hashes, so `git apply`
rejected it as a corrupt patch and the series failed at position 14. It described a feature — a VRAM
budget for private mirrors on discrete GPUs — that no commit in this repository ever shipped. The
series is 38 patches and every one applies to a pristine worktree of `d8123504938`.

## Verified on this build

- Patch series: all 38 llama patches apply to a pristine worktree of `d8123504938`.
- `test-backend-ops`: 11682/11682 on MTL0.
- `test-metal-memset`: all checks passed, including the adjacent-streams case that fails on the
  pre-fix engine.
- `swift test`: 424 tests, 15 skipped, 0 failures.
- SymPy engine integration: 14 tests, 1 skipped, 0 failures, against a real model.
- End to end: first launch to listening in 11 s, correct answers with `finish_reason: stop`, and
  **8.21 tok/s** decode on `Qwen3-14B-Q4_K_M`. Output integrity checked rather than inferred: a
  60-item enumeration returned all 60 in order, no duplicates and no gaps.

## About that 8.21 tok/s, stated precisely

It is **not comparable** to the 5.08 tok/s measured on an earlier beta, and reading it as a speedup
would be wrong. Different configuration:

- a **tensor split** across both D700s, not a layer split and not tensor parallel
- `TOSH_MGPU_TP` was never set; the log has zero TP entries
- both D700s report `peer group 0`, `not bridged` — peer copies cannot engage on this flat pair
- no cross-device handoff was confirmed for this run

It is a valid figure for the configuration it was taken in, and nothing more. Nothing in this
release is a fork-authored Metal speedup: the multi-GPU meta backend is upstream's, compiled
because `ggml-backend-meta.cpp` is in ggml's source list unconditionally. The `-DGGML_METAL_MGPU=ON`
flag that briefly appeared in this release's build script reads nothing in the tree and has been
removed.

## Tensor split vs layer split, measured properly

Since the 8.21 figure raised the question, both split modes were run back to back on this engine
and hardware: Qwen3-14B-Q4_K_M, `-ngl 99 -c 16384 -t 10`, both D700s, seed 42, temperature 0.

**Output is identical.** Both modes return the same 20 token IDs on the same prompt, so the tensor
split is correct on wave64 hardware:

    12095 13 576 6722 315 15344 374 21718 13 576 6722 315 17689 374 24081 13 576 6722 315 9856

**Throughput, tensor vs layer:**

| | tensor split | layer split |
|---|---|---|
| decode | **8.40 tok/s** | 5.12 tok/s |
| prompt eval | 15.23 tok/s | 10.16 tok/s |

So the tensor split is genuinely faster here, by 1.64x, and the 8.21 figure was not an artifact of
a sloppy measurement.

The reason is **not** peer-to-peer copies. `peer share 0.0%` and `peer bytes 0` in both runs,
because both cards report `peer group 0`, `not bridged`. The tensor split instead splits each matvec
across both cards and pays for it in host-staged collectives: 35520 allreduce exchanges over 221
tokens, exactly 160.01 per token per card, 1.59 GB through host memory. The layer split by contrast
shows 0 collectives and 222 plain cross-device copies in total.

**What the 1.64x does and does not mean.** It is not a measurement of collective efficiency, and
it must not be read as one. Layer parallelism and tensor parallelism are not two settings of the same
thing. A layer split assigns whole layers to cards and then runs them in sequence, because layer 20
cannot start until layer 19 finishes. For a single-token decode there is nothing to overlap with, so a
layer split over two cards delivers roughly what one card delivers, and
`docs/bench-baseline-2026-09-30.md` measures exactly that: Qwen3-4B-Q6_K generates 12.00 tok/s on a
single card and 11.96 tok/s on a layer split across two. The second card contributes no concurrency.

So the 8.40 against 5.12 gap measures the difference between a scheme that does not parallelise and
one that does. It is not evidence that tensor parallelism is cheap, and the collective path's cost
is **not yet measured**.

Two earlier readings of this data were wrong and are recorded here so they are not repeated. The
trace's `collective GPU` figure sums GPU-occupancy per command buffer across both cards, and those
intervals overlap, so it is not wall-clock and is not a share of runtime. And an attempt to derive a
collective cost from it assumed a layer split halves per-card work; it does not, because per-card work
is identical in both modes. Any percentage built on that assumption is void.

One thing that is settled: the exchange count. The design is two AllReduce per layer, one after the
attention output projection and one after the FFN down projection, because those are the only two
axis-0 row-parallel matmuls. The trace's 160.01 per token per card over 40 layers is those two
collectives seen as four directed exchanges each way, since with no peer group every crossing stages
through host memory. There is no surplus to remove.

One caveat worth knowing before benchmarking on this machine: a KeepAlive launchd agent
(`com.user.llama-server`, `-ngl 0`, 12 threads, port 8080) runs in the background. It was unloaded
for these measurements and reloaded afterwards. Its effect on the numbers turned out to be within
noise, but it is there.

Nothing above claims these are the last words on multi-GPU throughput for this hardware. It is one
measured configuration on two unbridged D700s, recorded so the next person starts from a number
rather than an impression.

## Install

Download the DMG, drag `ToshLLM.app` to Applications, and open it. The math runtime ships in the
bundle (CPython 3.13.16, SymPy 1.14.0, NumPy 2.5.3, SciPy 1.18.1, x86_64). The math tools are off
by default.

The server starts when you press Start, or at launch if "Start server automatically" is on in
Settings. That setting is off by default, so a fresh install shows a stopped server until you start
it — which is not a fault.

## Known

- **Intel x86-64 only, by decision.** There is no arm64 slice. For Apple Silicon, use upstream's
  release; the GCN fixes this fork carries are inert on an Apple GPU by construction.
- **Not notarized.** That is deferred to a future rebrand.
