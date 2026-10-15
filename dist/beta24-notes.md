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

## Split modes on two FirePro D700s

On the same unbridged pair, Qwen3-14B (40 layers, batch-1 decode) sustains 8.40 tok/s with tensor
split and 5.12 tok/s with layer split. Both modes emitted identical first 256 greedy token IDs and
identical text; chosen-token logprobs agree to a max absolute delta of 2.0e-03 with a mean of
1.5e-04, which is float summation order, not a difference in results. This is a throughput
difference, not a results difference.

These are two placements of one model, not two implementations of one placement. Tensor split needs
both cards at every layer. Layer split runs whole layers in sequence on one card and is therefore a
capacity mode: it is what lets a model too large for one 6 GB card run at all. Both modes do the same
per-card work. The difference is that tensor split overlaps the two cards and layer split does not.
No percentage overhead is reported for either, because none is measured.

| | tensor split | layer split |
|---|---|---|
| decode | 8.40 tok/s | 5.12 tok/s |
| prompt eval | 15.23 tok/s | 10.16 tok/s |

Method: engine 0.87.24-beta.1 (llama.cpp pinned `d8123504938` plus 38 fork patches), model
Qwen3-14B-Q4_K_M, `-ngl 99 -c 16384 -t 10 -fa auto`, both cards via `GGML_METAL_DEVICES=2`,
seed 42, temperature 0, batch-1 decode. Parity is N=1 per mode on a 256-token greedy continuation
with no warmup discarded. Throughput is N=1 per mode over 200 decoded tokens. Single runs, so treat
the throughput figures as indicative rather than settled. A KeepAlive launchd agent
(`com.user.llama-server`, `-ngl 0`, 12 threads) was unloaded for these runs and reloaded after;
its effect on the numbers was within noise.

**There is no single-card baseline for 14B.** The model is about 9 GB and one D700 has 6 GB, so
8.40 tok/s cannot be checked against a one-card run of the same model on this hardware, ever, and
is not checked against one anywhere above. Note also that 14B tensor-split decode at 8.40 tok/s is
slower than 4B on a single card at 12.00 tok/s: a larger model on two unbridged PCIe cards does not
buy back what the extra traffic costs.

### What is settled about the collective

The trace shows 160.01 exchanges per token per card over 40 layers. That is not surplus. The design
is two AllReduce per layer, one after the attention output projection and one after the FFN down
projection, because those are the only two axis-0 row-parallel matmuls; the exchange count is those
two collectives seen as four directed exchanges each way, since with no peer group every crossing
stages through host memory. Both cards report `peer group 0`, `not bridged`, so peer-direct copies
cannot engage and `peer share` is 0.0% in every run.

### What is not measured

The collective path's cost is **not yet measured**, and no figure is offered for it here.

Two earlier readings of this data were wrong and are recorded so they are not repeated. The
trace's `collective GPU` figure sums GPU-occupancy per command buffer across both cards, and those
intervals overlap, so it is not wall-clock and is not a share of runtime. And an attempt to derive a
collective cost from it assumed a layer split halves per-card work; it does not, because per-card work
is identical in both modes. Any percentage built on that assumption is void, and so would be any
percentage quoted against a modelled "2x the single-card number" ideal. A control that appeared to
work, `TOSH_MGPU_NOWAIT=1`, returned a bit-identical result because the flag is inert on this path:
decode on an unbridged pair takes the staged host-block route, which consults only
`TOSH_MGPU_WAIT_SATISFIED` and `TOSH_MGPU_BP_SATISFIED`. A control that changes nothing proves
nothing.

When a model has no valid tensor split, the engine exits 86 and the app relaunches once by layers.
That is a correctness fallback for arithmetic that cannot be divided, not a performance choice; no
code path anywhere picks layer split because it is expected to be quicker.

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
