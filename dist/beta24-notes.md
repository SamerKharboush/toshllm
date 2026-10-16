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

On the same unbridged pair, Qwen3-14B (40 layers, batch-1 decode) sustains more throughput with a
tensor split than with a layer split. The exact decode figures are not published yet; see below. Both modes emitted identical first 256 greedy token IDs and
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
| prompt eval, pp2048 | 37.84 tok/s | 29.45 tok/s |

Decode throughput for the two modes is not quoted here. An earlier N=20 measurement reported
coefficients of variation of 0.04% and 0.02%, which is not physically plausible on dual 274 W cards
in a 2013 chassis, so it is being re-measured under a longer interleaved protocol before any figure
is published. The spread of that run was too tight to be real, and a confidence interval resting on
an implausible standard deviation is worse than a loose one, because it invites the same retraction
as the figures it replaced.

Method: engine 0.87.24-beta.1 (llama.cpp pinned `d8123504938` plus 38 fork patches), model
Qwen3-14B-Q4_K_M, `-ngl 99 -c 16384 -t 10 -fa auto`, both cards via `GGML_METAL_DEVICES=2`,
seed 42, temperature 0, batch-1 decode. Parity is a single 256-token greedy continuation per mode.
Decode throughput is N=20 per mode with 3 warmups discarded. Prompt eval is `llama-bench -p 2048
-r 2`. A KeepAlive launchd agent (`com.user.llama-server`, `-ngl 0`, 12 threads) was unloaded for
these runs and reloaded after; its effect was within noise.

Prefill is measured with `llama-bench -p 2048`, not with the server's prompt-eval counter. The server
reports prompt throughput over however many tokens the prompt happened to contain, and on a short
prompt that is fixed overhead with no batch to amortise, which reads as a much lower number than
prefill actually is.

**There is no single-card baseline for 14B.** The model is about 9 GB and one D700 has 6 GB, so
8.584 tok/s cannot be checked against a one-card run of the same model on this hardware, ever, and
is not checked against one anywhere above.

Do not compare this figure against 4B numbers from a different quantisation. A 4B model here is
about 3.3 GB and the 14B model is about 9.0 GB, so a 4B model on one card and a 14B model on two
are not comparable quantities. Every comparison in this section is same model, same quantisation,
same hardware.

Prefill on this pair scales close to what the parameter count predicts. 4B (4.02B parameters)
reaches 116.18 tok/s prompt eval on a tensor split and 14B (14.77B parameters) reaches 37.84 tok/s.
The observed ratio is 3.07x for a 3.67x parameter increase, so 14B prefill is slightly ahead of a
parameter-proportional prediction rather than far below it. An earlier claim that 14B prefill was
17x off came from reading the server's prompt-eval counter on a 16-token prompt, which measures
fixed overhead, not prefill.

### What is settled about the collective

The trace shows 160.01 exchanges per token per card over 40 layers. That is not surplus. The design
is two AllReduce per layer, one after the attention output projection and one after the FFN down
projection, because those are the only two axis-0 row-parallel matmuls; the exchange count is those
two collectives seen as four directed exchanges each way, since with no peer group every crossing
stages through host memory. Both cards report `peer group 0`, `not bridged`, so peer-direct copies
cannot engage and `peer share` is 0.0% in every run.

### What the collective costs, measured against a control

This is the counterfactual rather than a derivation. The engine has
`TOSH_MGPU_ALLREDUCE_NOOP=1`, which keeps the split graph and every subgraph submission but performs
no reduction and no cross-device synchronisation. Same partitioning, same model, same context, same
thread count, one variable changed. The flag was confirmed to take effect before its numbers were
read: it prints a warning at startup, its output differs from the real run, and the exchange count
drops to zero.

N=20 per arm, 3 warmup runs discarded, 50 decoded tokens each, medians:

| | median | min | spread |
|---|---|---|---|
| tensor split, collectives on | 8.472 tok/s | 8.285 | 3.5% |
| tensor split, reduction skipped | 8.894 tok/s | 8.890 | 0.1% |

An earlier version of this measurement gave 5.41 ms per token with a standard error of 0.24 ms. That
interval is withheld. It rests on a standard deviation measured over 50-token runs with no warmup
between them, and the same protocol produced coefficient-of-variation figures tight enough to be
physically implausible on this hardware. A bound computed from an implausible spread is not a bound.

What did survive that run is the direction, not the magnitude: the no-op arm was much less variable
than the real arm. Collectives inject run-to-run variance into batch-1 decode, not only cost. The
size of that variance is being re-measured with 500-token generations, a 200-token warmup, and
interleaved A/B/A/B ordering, and the raw distribution will be published rather than a summary
statistic.

That is the whole headroom on this path, and it is not worth an optimisation project. The honest
summary is that host-staged collectives over unbridged PCIe on this pair cost single-digit percent
of decode, not a multiple.

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

## Hardware note

Each FirePro D700 is specified at 263 GB/s (384-bit GDDR5, 1370 MHz reference clock, 5480 MT/s
effective), which Apple's own Mac Pro technical specifications round to 264 GB/s. That is a paper
figure, not a measurement, and no fraction of peak is quoted anywhere in this document. The
179 GB/s figure that circulates for these cards is a 256-bit-class number belonging to a different
part; the D700 enumerates over PCI as a consumer Tahiti XT, which is how the mix-up happens.

The host is an Intel Xeon E5-2697 v2: Ivy Bridge-E, 12 cores and 24 threads at 2.7 GHz, 30 MB of
L3, DDR3-1866. It has AVX and F16C and no AVX2 and no FMA3, which is why this build ships with
`TOSH_NO_AVX2=1`. Decode throughput is flat from 8 to 16 threads (8.60 tok/s at each) and falls at
24 threads (7.99 tok/s) from SMT contention.

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
