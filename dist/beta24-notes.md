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

It is a valid figure for the configuration it was taken in, and nothing more. A single launch point
inside the range the longer measurement below reports (8.227 to 8.454 tok/s, median 8.406). Nothing in this
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
| decode, N=20, min | 8.227 tok/s | 5.021 tok/s |
| decode, N=20, median | 8.406 tok/s | 5.112 tok/s |
| decode, N=20, max | 8.454 tok/s | 5.138 tok/s |
| decode, N=20, coefficient of variation | 1.01% | 0.90% |
| prompt eval, pp2048 | 37.84 tok/s | 29.45 tok/s |

The tensor series, in run order: 8.442 8.411 8.407 8.405 8.407 8.405 8.338 8.375 8.454 8.411
8.415 8.436 8.445 8.452 8.342 8.227 8.232 8.231 8.246 8.231.

The layer series, in run order: 5.113 5.114 5.115 5.117 5.115 5.115 5.137 5.138 5.137 5.138
5.099 5.096 5.101 5.112 5.025 5.023 5.022 5.027 5.027 5.021.

The paired per-token difference over the same 20 blocks is **77.0 ms, range 74.7 to 79.1 ms**
(tensor mean 119.5 ms/token, layer 196.5 ms/token). The range is the observed spread of the 20
paired differences, not an interval computed from a standard deviation.

### Why an earlier version of this table was withdrawn

The first version of this measurement reported 8.584 and 5.146 tok/s with coefficients of variation
of 0.04% and 0.02%, or about 0.003 tok/s of standard deviation. On dual 274 W cards in a 2013
chassis that is not a plausible amount of variation, and it was not. It was two artifacts at once:
50-token generations with no warmup between them, and two arms measured as contiguous blocks rather
than interleaved.

Running the arms as contiguous blocks is the interesting mistake, because the data shows exactly what
it costs. This pair does not drift smoothly. It sits in a state, jumps to another state roughly every
five to ten runs, and both arms ride the same jump. Inside a single state the spread really is tiny:
runs 1 to 6 of the layer arm have a CV of **0.026%**, and runs 16 to 20 of the tensor arm have 0.087%.
Pool the whole session and the CVs become 1.01% and 0.90%. A short contiguous block inside one state
is what produced the withdrawn numbers, and a longer run would have produced them again.

So the session-level CV is quoted, not the block-level one, and the paired difference is quoted as a
range rather than as a confidence interval. The ratio between the arms is much more stable than
either arm alone (CV 0.55% across the same twenty blocks, against 1.01% and 0.90%), which is the
same fact seen sideways: the machine changes state, and both modes ride the change together.

Method: engine 0.87.24-beta.1 (llama.cpp pinned `d8123504938` plus 38 fork patches), model
Qwen3-14B-Q4_K_M, `-ngl 99 -c 4096 -t 12 -fa auto`, both cards via `GGML_METAL_DEVICES=2`,
seed 42, temperature 0, batch-1 decode. Each block is a fresh server process, a 200-token warmup
generation that is discarded, then 500 generated tokens timed by the server. Arms alternate block
by block (A/B then B/A). Parity is a single 256-token greedy continuation per mode. Prompt eval is
`llama-bench -p 2048 -r 2`. A KeepAlive launchd agent (`com.user.llama-server`, `-ngl 0`,
12 threads) was unloaded for these runs and reloaded after; its effect was within noise.

Prefill is measured with `llama-bench -p 2048`, not with the server's prompt-eval counter. The server
reports prompt throughput over however many tokens the prompt happened to contain, and on a short
prompt that is fixed overhead with no batch to amortise, which reads as a much lower number than
prefill actually is.

**There is no single-card baseline for 14B.** The model is about 9 GB and one D700 has 6 GB, so
8.406 tok/s cannot be checked against a one-card run of the same model on this hardware, ever, and
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

Prompt length has to be stated with any prefill number on this pair, because prefill is not
length-invariant and it falls after a peak. Swept with `llama-bench -n 0 -r 2` on 4B Q6_K:

| prompt length | layer pp | tensor pp |
|---|---|---|
| 512 | 78.30 | 141.37 |
| 1024 | 94.09 | 131.38 |
| 2048 | 95.62 | 115.76 |
| 4096 | 76.10 | 93.19 |

Tensor split peaks at 512 tokens and declines steadily from there, reaching 93 tok/s at 4096. Layer
split peaks near 2048. No figure in this section is quoted against a modelled peak, and none of
these is a fraction of one.

This also closes a conflict that had two tables disagreeing by 22%: a published baseline of 78.45 /
141.71 was pp512 and a later re-measure of 95.77 / 116.18 was pp2048. Both were correct. The pp512
re-measure lands within 0.2% of the published pair, so nothing had regressed; the two tables simply
were not measuring the same thing. Every prefill figure in this document now names its prompt length.

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
read: on an explicit `--split-mode tensor` run it takes the traced exchange count from **10560 to 0**
over 64 generated tokens, so the control is live on the path being measured.

N=20 blocks per arm, arms alternating block by block (A/B then B/A), each block a fresh server
process, a 200-token warmup generation discarded, then 500 generated tokens. Two sessions, run on
different days:

| machine state | collectives on | reduction skipped | cost |
|---|---|---|---|
| session 1, one state throughout | 8.406 tok/s | 8.813 tok/s | **5.49 ms/token** (range 5.20 to 5.67) |
| session 2, low state, 15 pairs | 8.229 tok/s | 8.545 tok/s | **4.50 ms/token** (range 4.36 to 4.62) |
| session 2, high state, 5 pairs | 8.410 tok/s | 8.800 tok/s | **5.26 ms/token** (range 5.00 to 5.51) |

The cost is **between 4.5 and 5.5 ms per token**, and that is the whole headroom on this path. Within
any single machine state the paired difference is reproducible to about ±0.15 ms; across states it
moves by around 20%, which is why the range is quoted rather than one number to two decimal places.
It is not worth an optimisation project. Host-staged collectives over unbridged PCIe on this pair
cost a few percent of decode, not a multiple of it.

An earlier version of this measurement gave 5.41 ms with a standard error of 0.24 ms over 50-token
runs, and an even earlier one reported a 525x variance ratio between the arms. Both are withdrawn.
The 525x came from measuring two arms as contiguous blocks, and the mechanism is worth recording
because it is the same mistake in both cases; see the state section below.

### Where a token's time actually goes

This section replaces an earlier claim that most of the GPU's headroom was unaccounted for. That
claim compared a measured rate against the card's spec-sheet bandwidth, and a spec-sheet number
is a modelled denominator, not a measurement. It is withdrawn. What follows compares the engine
against itself, on cells measured the same way with the same binary.

Method: engine 0.87.24-beta.1 at `d81235049`, one binary for all three cells, tensor split,
`-ngl 99 -t 12 -fa 1 -b 2048 -ub 512 -p 512`, `r=3`, generation windows as listed, warmups
discarded by `llama-bench`'s own protocol. `TOSH_FA_AMD=1` is set throughout: on the tensor
split, `-fa 1` requires it, and without it the build refuses this configuration outright (see
below).

| model | weights | tg64 | tg128 | ms per token |
|---|---:|---:|---:|---:|
| Qwen3 4B Q4_K_M | 2.497 GB | 19.49 | 19.48 | 51.3 |
| Qwen3 4B Q6_K | 3.306 GB | 17.84 | 17.84 | 56.1 |
| Qwen3 14B Q4_K_M | 9.002 GB | 8.44 | 8.43 | 118.6 |

The 64-token and 128-token windows agree to within 0.1%, so window length is not a factor in
these cells.

Fitting the three cells gives **10.57 ms per GB** as the marginal cost of weight traffic — 94.6
GB/s — plus a **23.1 ms cost per token that does not depend on model size** at all. The fit
reproduces the measurements to +3.6%, −3.5% and +0.2%.

So at 14B, and this is the whole of it: **95 ms of a 119 ms token is weight traffic, and 23 ms
is a fixed per-token cost.** The traffic term has no obvious lever — it is the weights being
read, once each, at a rate this machine sustains. The 23 ms is where any remaining work lives,
and the collective is only part of it: the ablation above puts the collective at 4.5–5.5 ms,
about a fifth of the fixed term and a bit over 4% of a token.

The denominator here is a **marginal** rate from a fit across three models of different depth,
not an independently measured bandwidth. There is no bandwidth microbenchmark on this machine
(`clpeak`, `STREAM` and friends are all absent), so 94.6 GB/s should be read as "the rate this
build actually charges per additional GB", not as the card's ceiling. It is, however, close to
the 94–110 GB/s that the same class of hardware sustains in practice, and it is measured here
rather than assumed.

One thing this does not settle: a 30-second stack sample during decode finds the main thread
blocked roughly three-quarters of the time in a Metal command-buffer wait, with every other
thread idle. That wait is where the traffic time *appears* — it absorbs queued GPU work — so it
does not prove the transfer is the cost. It does establish that the host is waiting rather than
computing, which is why host-side thread counts can still move decode even when the bandwidth
term looks saturated.

### A required variable that fails confusingly, and a stale benchmark binary

`-fa 1` on the tensor split requires `TOSH_FA_AMD=1`. Without it, the standard flash-attention
path builds a `mul_mat` whose operands carry split axes the meta backend cannot reconcile, and
this build stops. `llama-server` stops correctly, with the reason and the remedy:

```
ggml_backend_meta: unsupported mul_mat split states: ...
This model has no two-way tensor split. Restart with --split-mode layer.
```

and exits 86. `llama-bench` in this bundle does **not**: it reports a bare abort with a
backtrace, because the binary shipped in `build-static/bin` predates the patch that introduced
those named exits. Rebuild before using `llama-bench` as an independent timing gate, and set
`TOSH_FA_AMD=1` when comparing against the numbers above.

Every log on this machine also carries a non-fatal Metal shader compilation failure ("exceed the
local data storage limit") at startup, four occurrences per server start. It predates this
release and does not block anything, but it means at least one kernel in the AMD path is not
compiling and something is substituting for it. That is noted rather than resolved.

### The machine sits in discrete states, and that is why the first CVs were impossible

Two arms measured as contiguous blocks will each land inside whatever state the machine is in, and
inside a state the spread is genuinely tiny: the layer arm's first six runs have a coefficient of
variation of 0.026% and the tensor arm's last five have 0.087%. Pool a whole session and the same
data gives 0.90% and 1.01%. The withdrawn 0.04% and 0.02% were real measurements of one state, not
noise and not a bug.

The pair flips state about every five to fifteen runs. In session 2 it stepped at block 16 and the
step is visible in both arms at once: real went 8.228 to 8.417 tok/s, and the reduction-skipped arm
went 8.545 to 8.787. Both moved about 2-3% in the same direction in the same block. Session 2's
real arm shows a 2.21% gap between states, its no-op arm 2.98%.

The arm that does *less* host work moved further, which points at the GPU rather than at the CPU, but
the cause is not identified and no cause is claimed. `machdep.xcpm.gpu_thermal_level` reads 0 and
`pmset -g therm` reports no thermal or performance warning at either state, so this is not the
machine reporting a throttle. What can be said with confidence is that the states are discrete, that
both arms ride the same one, and that a protocol which does not interleave will report a spread that
describes one state as though it described the hardware.

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

### The flag sweep, run deliberately

The 39th unsatisfiable-split failure mode was found by accident: someone set
`GGML_METAL_WAVE64_DECODE_DISABLE=1` on a tensor split to see what would happen, and the engine
aborted in the KV-cache `set_rows` path. An abort found by accident implies the others are latent,
so all eight combinations of the three knobs that can be varied were run on purpose, on the 14B, and
each was required to either reach a listening server or exit 86 with a named reason.

| split mode | `GGML_METAL_WAVE64_DECODE_DISABLE=1` | `GGML_METAL_CONCURRENCY_DISABLE=1` | result |
|---|---|---|---|
| tensor | off | off | reached server |
| tensor | off | on | reached server |
| tensor | **on** | off | **exit 86**: `set_rows source and destination are split differently (cache_k_l0 (view))` |
| tensor | **on** | on | **exit 86**, same reason |
| layer | off | off | reached server |
| layer | off | on | reached server |
| layer | on | off | reached server |
| layer | on | on | reached server |

Every combination has a defined outcome. None of the eight produced a bare `GGML_ASSERT`, a
segfault, or a hang, so no combination is silently broken.

The wave64 flag is fatal on a tensor split and harmless on a layer split, which is consistent rather
than surprising: the failure is a KV-cache tensor whose rows cannot be divided across two cards, and
a layer split does not divide any tensor's rows. Concurrency is a pure scheduling choice and is inert
on both. Both flags are therefore safe to leave in their default state and neither is a workaround for
anything.

Nothing above claims these are the last words on multi-GPU throughput for this hardware. It is one
measured configuration on two unbridged D700s, recorded so the next person starts from a number
rather than an impression.

### Speculative decoding: nothing to draft with

Decode here is slow enough that speculation is worth a look, so it was looked at. There is no draft
model to run against this target. Qwen3-14B has no MTP head: its `config.json` carries no MTP keys
and the GGUF holds 443 tensors, none of them `nextn`. No Qwen3-14B DFlash exists either; that family
skips 14B at every generation. The one ready-to-run EAGLE-3 speculator for this target is an 855 MB
GGUF, and the fork's own memory planner returns negative room for it on this pair before accounting
for the planner being 7.4x optimistic on KV for a dense model.

There is also a quantisation gate on any future gain. The wave64 multi-token kernels exist only for
`q6_K` and `q8_0`, and Qwen3-14B-Q4_K_M is 75.7% Q4_K by per-token weight bytes. The upstream 27B
figure cited in this fork's changelog was measured on UD-Q6_K, where the whole of the weight traffic
takes the fast path. No percentage is projected from the byte fraction, because a byte fraction is
not a time fraction.

One trial was run anyway, because it needed no model, no download and no VRAM:
`--spec-type ngram-mod`, which shares the multi-token verify path a learned draft would use. On a
single fresh 500-token generation the engine drafted nothing — it printed no acceptance line at all
and ran at 8.36 tok/s against a plain 8.42. An earlier protocol that re-sent the same prompt across
five cached segments reported an acceptance rate of 1.00000 (95 accepted of 95, mean draft length
24.75) and 22.1 tok/s. **That figure is withdrawn before publication.** Re-sending one prompt keeps
the model's own earlier output in context, so the n-gram matcher had a literal 24-token string to
copy; it measured a copy loop, not a conversation. It is recorded here because it is the third
measurement artifact this session, and the pattern is what matters: two of the three came from the
apparatus rather than the machine.

## Hardware note

Each FirePro D700 is specified at 263 GB/s (384-bit GDDR5, 1370 MHz reference clock, 5480 MT/s
effective), which Apple's own Mac Pro technical specifications round to 264 GB/s. That is a paper
figure, not a measurement, and no fraction of peak is quoted anywhere in this document. The
179 GB/s figure that circulates for these cards is a 256-bit-class number belonging to a different
part; the D700 enumerates over PCI as a consumer Tahiti XT, which is how the mix-up happens.

The host is an Intel Xeon E5-2697 v2: Ivy Bridge-E, 12 cores and 24 threads at 2.7 GHz, 30 MB of
L3, DDR3-1866. It has AVX and F16C and no AVX2 and no FMA3, which is why this build ships with
`TOSH_NO_AVX2=1`. Decode throughput is flat from 8 to 16 threads (8.60 tok/s at each) and falls at
24 threads (7.99 tok/s) from SMT contention. Those are `llama-bench -n 128 -r 3` figures, which are
short runs and land wherever the machine happens to be; they are for comparing thread counts against
each other, not for comparing against the interleaved numbers above.

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
