# Dynamic MoE on the D700: correct, and slower than the host (smoke, not a row)

Strata's design (hot experts in VRAM, every expert in RAM, the CPU computes the misses) is
already in this engine as Dynamic MoE. This is the first time it has run on the D700.

## Method

| | |
|---|---|
| engine | `vendor/llama.cpp/build-static/bin/llama-server`, sha256 `8ebda2454b4df9ac348dc289cc44cb7e82af1885aa1c3c2ea78acbc5550b9d0d` (the beta.2 engine) |
| model | `ornith-1.0-35b-Q6_K.gguf` (qwen35moe) |
| launch | `-c 4096 -t 12 -fa auto --parallel 1`, `TOSH_FA_AMD=1`; reference `-ngl 0`; cell `--dynamic-moe on`, one card (no `GGML_METAL_DEVICES`) |
| request | chat "Explain what a binary search tree is.", 400 tokens, temperature 0, seed 1234, `cache_prompt: false`, 19-token prompt |
| N | **1 per cell**, no warmup discarded |
| environment | **contaminated**: an unrelated idle `llama-server` (Qwen3-14B, `-ngl 0`, 0% CPU) was resident throughout |

N=1 beside another resident server, so these are not rows and are not published as figures.

## What it planned

`mode=PLAN_FULL_HOST_DMOE reason=FULL_HOST_SAFE warnings=COVERAGE_CONSTRAINED,PROMPT_CACHE_REDUCED
rss=27.5GiB vram=4.4GiB hot=1.4GiB coverage=1.06 CONSTRAINED ub=1024`

Only 1.4 GiB of the 6 GB card became the HOT expert arena.

## What it did

| cell | decode tok/s | prompt eval tok/s | output |
|---|---|---|---|
| `-ngl 0` (reference) | 10.17 | 16.48 | coherent, 0 CJK, no repeated tail |
| `--dynamic-moe on` | 6.74 | 2.34 | coherent, 0 CJK, no repeated tail; differs from the reference from character 70 |

- **Correctness:** Dynamic MoE does **not** show ticket 66's collapse. The divergence at character 70 is a
  different-but-sensible paraphrase. It is the same class as the GPU-vs-CPU difference in
  `fidelity-against-the-shipped-build-2026-10-20.md` (from character 85), not junk.
- **Speed:** on this card it loses to the host on both decode and prefill. The prefill figure is a
  19-token prompt and says little.

## What this suggests to measure next

1. The arena is constrained to one card's 1.4 GiB. **`GGML_METAL_DEVICES=2` would be an inert control
   here:** the planner takes the first GPU (`common/tosh-plan.cpp:352`, `ggml_backend_dev_by_type(GPU)`),
   so Dynamic MoE is single-card by design. A two-card arena is a code change, not a flag.
2. ~~Find whether the CPU executor runs concurrently with the card.~~ Answered from the source: it does.
   `tosh-moe/tosh-dmoe.h:1-4` has the card publish a layer's routing and signal; the host computes the
   non-resident experts while the card computes the resident ones; the card waits for the answer before the
   join. This is Strata's overlap. The cost to find is therefore the rendezvous or the card's share, which
   `TOSH_DMOE_STATS` ("join waited in N of M layers") and `TOSH_DMOE_TIMELINE` measure.
3. Re-run with the other server stopped, N >= 5, warmups discarded, before anything becomes a row.

## Clean series, and the control that did not take effect

Same engine, model, launch and request as above. The unrelated server (launchd `com.user.llama-server`)
was deregistered first (`launchctl bootout`; a plain kill respawns it). Cells alternated
ref, dmoe, ref, dmoe; each server did 1 warmup (discarded) and 3 measured requests: **N=6 per cell**.

| cell | decode tok/s | prompt eval tok/s (19-token prompt) |
|---|---|---|
| `-ngl 0` | 10.7611 (sd 0.0548) | 20.2366 (sd 0.6105) |
| `--dynamic-moe on`, as launched | 6.7555 (sd 0.0085) | 2.5116 (sd 0.0083) |

**The second row is not Strata's overlap.** Both dmoe servers logged
`llama_tosh_dmoe_budget: under 788 MiB left for experts, mixed execution stays off`. The planner
reported `hot=1.4GiB` and the runtime budget then found less than its 788 MiB minimum, so the
CPU-and-card mixed execution never ran. The row measures Dynamic MoE with mixed execution switched off. It
says nothing about the overlap on this card (CLAUDE.md rule 2).

Why: `src/llama-tosh-dmoe.cpp:1785-1788` computes the arena as VRAM free at start, less
`TOSH_DMOE_RESERVE_MIB` (default **2560 MiB**), less 64 MiB overhead, less three prefill slots the
size of the largest expert bank, less the model, context and compute on the card. On a 6 GB card the
2560 MiB reserve alone is most of what the weights leave. The app's placement rule reserves 1 GB per card.

Two defects follow, whatever the overlap measures:
1. The planner and the runtime budget disagree: the planner promises 1.4 GiB and the runtime grants
   none, with no change in the reported plan.
2. Prefill with mixed execution off spends 22.1 s "issuing uploads" (320 uploads) and 6.2 s waiting
   for ids per server lifetime (`tosh_dmoe:` stats line). That is where the prompt-eval loss is.

## Root cause: the planner sizes prefill slots from the file, and a 64-lane card fuses gate and up

A second control was inert too: `TOSH_DMOE_RESERVE_MIB=1024` changed nothing, because the planner
overwrites it (`common/tosh-plan.cpp:1088-1089`, `setenv(..., 1)`); the log read `reserve 768` with and
without it. The knobs that reach the runtime are `TOSH_AUTO_RESERVE_MIB` / `TOSH_AUTO_MIN_ARENA_MIB`.

The planner (dry run, `TOSH_AUTO_DRY_RUN=exit`) and the runtime (`-lv 4`) side by side, MiB:

| term | planner | runtime |
|---|---|---|
| VRAM free | 5232 | 5232 |
| model + context + compute | 2412 (probe: 1584 + 142 + 686) | 2414 (1584.88 + 80 KV + 62.81 RS + 686.01) |
| prefill slots (3 x largest expert tensor) | **~631** | **1260** |
| reserve + overhead | 768 + 64 | 768 + 64 |
| expert arena | 1357 | **727** (< 788 minimum: mixed execution off) |

- `src/llama-model.cpp:3720-3726`: when `TOSH_METAL_SIMD_WIDTH=64` (the D700 probes as 64-lane), the
  loader fuses each layer's `ffn_gate_exps` and `ffn_up_exps` into one `ffn_gate_up_exps`, twice the
  size of either.
- `src/llama-tosh-dmoe.cpp:1781`: the runtime sizes a slot from that fused tensor (420 MiB).
- `common/tosh-plan.cpp:195`: the planner sizes it from the GGUF's separate tensors (~210 MiB).

So on every wave64 card (GCN, Vega) the planner overstates the arena by 3 x the size of one half, and
here that is exactly the margin between a 1.3 GiB arena and none. RDNA (32-lane) is unaffected, which is
why this never showed on the RX 6700 XT the feature was built on.

Fix (to be written as a patch): the planner counts a layer's gate+up as one tensor when the loader will
fuse them (the same condition: SIMD width 64 and no `TOSH_MOE_GATE_UP_DISABLE`). Separately, the runtime
should say in the plan line that the arena it got differs from the one the plan reported.

## With the fusion off, mixed execution runs, and it decodes above the host

`TOSH_MOE_GATE_UP_DISABLE=1` halves the prefill slot (runtime: slots 630, base 2250, arena 1521 MiB),
and the runtime logs `mixed expert execution on 40 layers, 0 resident experts, VRAM arena 1476.60 MiB,
12 host threads`. **The control took effect**, confirmed in each server's exit stats: 64080 host jobs,
card hit rate 38.94% (round 1) and 40.13% (round 2), host time per job 363.4 / 356.1 us.

Method: same engine (`8ebda245...`), model, `-c 4096 -t 12 -fa auto --parallel 1`, `TOSH_FA_AMD=1`, request
as above; ref, dmoe, ref, dmoe, one server per cell per round, 1 warmup discarded and 3 measured each,
**N=6 per cell**, nothing else resident.

| cell | decode tok/s | prompt eval tok/s (19-token prompt) | output over the 6 requests |
|---|---|---|---|
| `-ngl 0` | 10.6234 (sd 0.1406) | 18.5182 (sd 0.7003) | identical every time, 1659 chars |
| `--dynamic-moe on`, `TOSH_MOE_GATE_UP_DISABLE=1` | **13.0498** (sd 0.0225) | 21.8095 (sd 0.0582) | coherent every time, 0 CJK; **1576-1686 chars, not identical between greedy requests** |

The two cells' ranges do not overlap: ref 10.464-10.772, dmoe 13.016-13.081.

**Not deterministic.** At temperature 0 with a fixed seed the host path repeats itself exactly, and Dynamic
MoE does not. Which experts sit in the arena changes from request to request, so the summation order and
rounding change too. Every answer is coherent; none is the same text. This goes next to any use of the row.

The prompt column is a 19-token prompt: it says nothing about long-prompt prefill, which is untested.

## Patch 0046: the plan counts a fused gate/up, and the default launch runs mixed execution

`patches/llama/moe/0046-the-plan-counts-a-fused-gate-and-up-as-one-prefill-slot.patch` applies the loader's
fusion rule in the planner's tensor scan. Engine built with `TOSH_AVX1=1 SKIP_WHISPER=1 SKIP_IMAGE=1
./scripts/build-engines.sh`: sha256 `21e642e5eed978192e9e0642bc24938f4f792c0edf1f598fc82e8419f8be5b70`,
"0 AVX2/FMA mnemonics", series 51 of 51 clean. The beta.2 engine (`8ebda245...`) is kept aside.

Dry run with the fusion on: the planner now predicts 726 MiB for f16 / ub 1024 (the runtime measured 727
before the fix) and selects `q8_0` KV with ub 512 for 791 MiB, above the 788 minimum. At load the
runtime grants 792-796 MiB and logs `mixed expert execution on 40 layers`.

Method: engine `21e642e5...`, same model, `-c 4096 -t 12 -fa auto --parallel 1`, `TOSH_FA_AMD=1`, same
request; ref, fused, unfused, ref, fused, unfused; one server per cell per round, 1 warmup discarded and
3 measured, **N=6 per cell**, nothing else resident. Every dmoe server's exit stats show 64080 host jobs.

| cell | decode tok/s | range | prompt tok/s (19 tokens) | card hit rate | output |
|---|---|---|---|---|---|
| `-ngl 0` | 10.8932 (sd 0.3934) | 10.686-11.693 | 19.5795 (sd 1.3317) | - | 1659 chars, identical x6 |
| `--dynamic-moe on` (default: fused, q8_0, ub 512, arena 788 MiB) | **13.2231** (sd 0.1428) | 13.107-13.417 | 21.8147 (sd 0.0834) | 28.33 / 28.39% | coherent x6, 0 CJK, 1587-1679 chars |
| `--dynamic-moe on`, `TOSH_MOE_GATE_UP_DISABLE=1` (f16, ub 1024, arena 1477 MiB) | 13.2513 (sd 0.1021) | 13.046-13.311 | 21.8628 (sd 0.1240) | 39.70 / 39.37% | coherent x6, 0 CJK, 1578-1679 chars |

- The two dmoe cells overlap: **one result, not two**. No unfuse patch is needed.
- Hit rate 40% vs 28% buys nothing measurable, so the card's share is not what limits decode here; the host
  executor is (`host time per job` ~355 us, gate/up ~235 us of it). That is the next lever, not a bigger arena.
- The ref range includes one 11.693 request; its sd is larger than in the earlier series (0.1406).
- The non-determinism stands: dmoe answers differ request to request at temperature 0, all coherent.
- Not yet measured: long-prompt prefill, `-c 16384` (the app's launch), other MoE models, and the beta.2
  engine's dmoe with the fusion on (known: mixed execution off, 6.7555 tok/s above).

## The app's launch, with a long prompt

Method: engine `21e642e5...` (0046), `ornith-1.0-35b-Q6_K.gguf`, the launch the app builds for R24:
`-c 16384 -t 12 -fa auto --load-mode none --cache-ram 2048 --cache-reuse 256 --parallel 1`, `TOSH_FA_AMD=1`;
ref adds `-ngl 0`, dmoe adds `--dynamic-moe on`. Two requests per server, each 1 warmup discarded and 3
measured: the BST prompt above (19 prompt tokens, 400 generated) and the first 9000 characters of
`README.md` with "Summarise this document in three sentences." (2402 prompt tokens, 32 generated);
temperature 0, seed 1234, `cache_prompt: false`. ref, dmoe, ref, dmoe: **N=6 per cell**, nothing else resident.

Control: both dmoe servers logged `mixed expert execution on 40 layers ... VRAM arena 787.54 MiB, 12 host
threads`; the plan was `ctx=16384 kv=q8_0 ub=512` with `RESERVE_LOWERED` (reserve 512 MiB); exit stats
69200 host jobs, card hit rate 28.13 / 27.65%.

| cell | decode tok/s | prompt eval tok/s |
|---|---|---|
| `-ngl 0`, 19-token prompt | 11.6169 (sd 0.0174) | 22.4676 (sd 0.2529) |
| `--dynamic-moe on`, 19-token prompt | **13.3412** (sd 0.0419) | 21.8754 (sd 0.1090) |
| `-ngl 0`, 2402-token prompt | 11.1392 (sd 0.0505) | 28.2874 (sd 0.2243) |
| `--dynamic-moe on`, 2402-token prompt | **12.3770** (sd 0.0433) | **71.9468** (sd 0.0880) |

No pair of ranges overlaps. Outputs: ref identical x6 (1659 chars); dmoe coherent x6, 0 CJK, 1604-1689
chars, not identical. The long-prompt answers start with the same 130 characters in both cells.

Not runnable here: a second MoE model. The 35B is the only MoE GGUF in `~/models` and on `/Volumes/micron`.
