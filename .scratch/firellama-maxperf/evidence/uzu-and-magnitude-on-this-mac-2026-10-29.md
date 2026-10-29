# uzu and magnitude on this Mac

Date: 2026-10-29. Asked: could either engine replace our llama.cpp fork, or lend it an idea.
Machine: Mac Pro 6,1, Xeon E5-2697 v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700 (GCN 1.0),
macOS 15.8 (24H23).

## Receipts

Read from shallow clones: uzu `1a98bbb`, magnitude `0fcf792`.

- **uzu (trymirai/uzu)**
  - Its Metal backend refuses every non-Apple GPU:
    `crates/uzu-engine/src/backends/metal/metal_extensions/device_extensions.rs`,
    `newest_supported_apple_gpu_family`:
    `.expect("unsupported Metal device: uzu requires an Apple GPU")`. The D700 reports no
    Apple GPU family, so uzu cannot use either card.
  - Models must first be converted to uzu's own format with its `lalamo` tool, from HF
    safetensors; it does not read GGUF.
  - Its CPU and WebGPU backends exist, but not running them is deliberate: the CPU path would
    need a re-download of the 35B in another format, and our host path is already measured.
  - **Not run here.**
- **magnitude (magnitudedev/magnitude)**
  - Its stated floors are in `inference/docs/compatibility.md`:
    - "Metal | macOS arm64 | Any Apple silicon Mac running macOS 15";
    - "Intel Macs: CPU only";
    - the x86 tiers are x86v2 (SSE4.2), x86v3 (AVX2+FMA) and x86v4 (AVX-512). There is no AVX1
      tier, so this Xeon falls to x86v2.
  - The engine log of the run below confirms the tier: `isa=x86v2`, `backend: Cpu`.
  - It reads GGUF directly. It identified our Ornith 35B Q6_K as a "Qwen3.6 35B-A3B" variant
    and offered its DFlash drafter (`magnitudedev/Qwen3.6-35B-A3B-DFlash-GGUF`, 421 MB).
  - **Run here, on the CPU only.**

## The one runnable cell: magnitude CPU against our host path

Both engines were timed by the same client, scratchpad `ab-bench.py`:
- an OpenAI streaming chat request, temperature 0, 128 tokens out;
- the prompt is the BST prompt;
- TTFT runs from the request to the first content chunk;
- decode is (chunks - 1) / (time of last chunk - time of first);
- request 1 of each cell is a warmup and is discarded.

The cells ran one after the other, never together. Before the second cell, magnitude's service
and model were stopped.

| cell | N | decode tok/s, mean (sd) | TTFT s, mean (sd) | warmup decode |
|---|---|---|---|---|
| magnitude 0.2.14 CPU (x86v2), Ornith-1.0-35B Q6_K | 2 | 0.3170 (0.0039) | 94.595 (0.819) | 0.283 |
| ours, `-ngl 0`, Ornith-1.0-35B Q6_K | 5 | 9.8485 (0.0304) | 0.261 (0.020) | 9.905 |

Method:
- **magnitude:**
  - Intel installer `magnitude-desktop-darwin-x64.dmg`, sha256 c9e70a9f…; engine release 0.2.14;
  - run from a scratch copy of the app, with the service started by `magnitude serve`;
  - default serving settings: 256K context, KV codec k8v4, reasoning on;
  - no drafter.
  - N is 2 because each request took about 8 minutes. The run was stopped after request 3.
- **ours:**
  - engine d81235049 plus patches 0001–0053, AVX1; llama-server sha256 2bb65447…;
  - `-ngl 0 -c 16384 -t 12 -fa auto --load-mode none --parallel 1 --cache-ram 0`, with
    `TOSH_FA_AMD=1`, which is the R24 launch.
- **Text:**
  - both engines are deterministic: every timed response was identical within its engine;
  - both texts are coherent;
  - they agree for the first 226 characters, then word the same step differently. Magnitude
    runs bf16 activations and a k8v4 KV cache, so identical text is not expected.

Reading: on this machine magnitude is a CPU engine without an AVX path. Its numbers are an
observation of that configuration, not a bound on what its kernels do on supported hardware.
Neither engine can replace ours here: uzu cannot run on these GPUs at all, and magnitude runs
the 35B at 0.317 tok/s against our 9.85.

## What is worth taking from them

1. **DFlash block drafting, with magnitude's drafter for Qwen3.6-35B-A3B.**
   - Our engine already has `--spec-type draft-dflash`.
   - Their GGUF does not load in it: `key dflash.attention.causal has wrong type arr but
     expected type bool`. The drafter declares per-layer causality `[T,T,T,T,T,F]`, the same as
     its sliding-window pattern; our loader takes a single bool.
   - Whether it can pay on the host path is bounded by the cost of one verify step. From
     `llama-bench -ngl 0 -t 12 -fa 1 -n 0 -r 3`, same engine and model:

     | tokens per step | 1 | 2 | 4 | 8 | 16 |
     |---|---|---|---|---|---|
     | t/s | 9.41 (0.15) | 13.18 (0.12) | 18.35 (0.14) | 12.55 (1.26) | 17.30 (1.80) |

   - A 4-token verify costs 0.218 s, about two single-token steps (0.106 s each). Drafting 3
     tokens per round pays only if more than about one is accepted per round, before the
     drafter's own cost.
   - A 16-token verify costs 0.925 s, so it would need about 8 accepted per round.
   - The fix was delegated to OpenCode (`9router/Mocca#high`). The run made no edits: four
     model steps of about 5 minutes each, then `provider.transport: Timed out waiting for
     response headers`. The orchestrator wrote it instead; it is patch 0054.

## DFlash with magnitude's drafter, after patch 0054

Patch 0054 (`patches/llama/moe/0054-dflash-drafts-declare-causality-per-layer.patch`):
- reads `dflash.attention.causal` as a bool or one bool per layer;
- accepts a mixed pattern only when it matches the SWA pattern, and then sets a new
  `LLAMA_NON_CAUSAL_TYPE_DENSE_ONLY`: the SWA cache's mask stays causal and the dense cache's
  mask becomes non-causal;
- the load log at `-lv 4` reads `DFlash per-layer causality = CCCCCN, non_causal_type = 3`.

Regression: Nemotron-3.5-Bolt-E4B's own drafter, which declares a scalar `false`, still loads
and drafts (24/39 and 17/33 accepted), and its text is coherent.

Method:
- engine d81235049 plus 0001–0054, AVX1; llama-server sha256 c64c537b…;
- target Ornith-1.0-35B Q6_K, with the R24 host launch on llama-server:
  `-ngl 0 -c 16384 -t 12 -fa auto --load-mode none --parallel 1 --cache-ram 0`, `TOSH_FA_AMD=1`;
- the drafter is `Qwen3.6-35B-A3B-DFlash-Q8_0.gguf`, sha256 70ae9123…:
  - on the CPU: `-ngld 0`;
  - on card 1: `GGML_METAL_DEVICE_INDEX=1 … -ngld all -devd MTL0`;
- requests go to `/completion` with a raw ChatML prompt, greedy, 128 tokens, `cache_prompt
  false`;
- each server serves 4 requests and the first is discarded;
- the cells alternate (plain, CPU drafter, card drafter) for 3 rounds on the code prompt and 2
  rounds on the prose prompt;
- the timing is the server's `predicted_per_second`.

Code prompt (the BST prompt), 3 drafts per round:

| cell | N | decode tok/s, mean (sd) | accepted / drafted | text equals plain |
|---|---|---|---|---|
| plain | 9 | 10.0509 (0.0473) | — | — |
| drafter on CPU | 9 | 10.2740 (0.1063) | 68 / 80 | yes, 9 of 9 |
| drafter on card 1 | 9 | 10.8481 (0.0825) | 73 / 87 | yes, 9 of 9 |

Earlier on the code prompt, at 7 and 15 drafts with the drafter on the CPU, N=2: 7.53 and
7.21 tok/s at 7 drafts, 7.89 and 7.92 at 15. Every text equalled plain.

Prose prompt ("a short story about a lighthouse keeper who finds a message in a bottle"),
drafter on card 1:

| cell | N | decode tok/s, mean (sd) | accepted / drafted | text equals plain |
|---|---|---|---|---|
| plain | 6 | 10.0352 (0.0395) | — | — |
| 2 drafts | 6 | 10.1341 (0.1942) | 43–46 / 50 | no, diverges at char 236–359 |
| 3 drafts | 6 | 10.2264 (0.0597) | 44 / 54 | no, diverges at char 296 |
| 4 drafts | 6 | 10.0137 (0.0752) | 46 / 64 | no, diverges at char 296 |

Control for the mask (rule 2), drafter on the CPU, code prompt, with a temporary environment
switch that ignored DENSE_ONLY and has since been removed:
- at 3 drafts, acceptance was unchanged: 68/80;
- at 7 drafts it changed: 53/77, then 2/14, against 51/77 with the per-layer mask.

So the control does take effect. The per-layer mask shows no acceptance gain on this prompt;
what it buys is that the drafter loads at all.

Reading:
- On the code prompt, the drafter on card 1 moves host decode from 10.05 to 10.85 tok/s. The
  difference is about ten times either cell's sd.
- On prose the difference is 0.19 tok/s at 3 drafts, three to five times the sd.
- On prose the text is **not** identical to plain decoding. Each drafted cell departs from it
  at a fixed point and stays coherent. Inferred, not shown: the target's multi-token verify
  rounds differently from its single-token decode, so a near-tie can flip its argmax. The code
  prompt hit no such tie.
- With the drafter on card 1, the 2-draft cell's acceptance varied between requests of the
  same server, so its text varied too.
- Not run: the app's own launch with a drafter. The 67 placement rule keeps a host-placed model
  away from every card, and putting the drafter on card 1 breaks that rule.
2. **Per-device launch tuning.** Magnitude times candidate launch parameters (rows per program,
   worker counts) on the actual device and stores the winner. Its log shows `tuned
   routed_combine […] {"ROWS": 8, "cpu.tier": 0, …}`. This is added to the 0a GCN mat-vec brief
   as a question: which of nsg / nr0 / threads per threadgroup could be chosen this way at device
   init.
3. Nothing to take from uzu's code for this hardware. Its stated idea, traceable computations
   checked against a reference, is what our coherence gates already do.
