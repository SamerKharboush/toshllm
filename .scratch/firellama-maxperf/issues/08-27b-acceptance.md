# 08 — 27B acceptance run

Status: resolved
Type: task

## Question

Does the 27B ternary MoE-adjacent acceptance model load and run at the fastest sustainable
setting on this Mac Pro, and is the answer coherent?

## Answer

**Yes, on a layer split with the shared-event hand-off off.** 6.22 tok/s generation,
11.54 tok/s prefill, coherent output, both D700s registered.

### Benchmark

Ternary-Bonsai-2-27B-PQ2_0 (6.70 GiB, 26.90 B params, arch `qwen35`), engine 0.87.11 +
patch 0114, 12 threads (physical), `-fa 1`, `GGML_METAL_DEVICE_LIST=0,1`,
`GGML_METAL_CONCURRENCY_DISABLE=1`, `--split-mode layer`, `-r 2`:

| test | t/s |
| --- | --- |
| pp512 | 11.54 ± 0.01 |
| tg64 | 6.22 ± 0.00 |

Reproduced to 0.01 across `-r 1`/`-r 2` and at `p=8/256/512`. Generation is flat at
6.20-6.22 tok/s for n=32/64/96, so it is not a warm-up artefact. Cross-device hand-off tally:
`events=0 peer=0 generic=132` — the generic host staging path, as expected with events off.

Both GPUs registered (`device 0` / `device 1`, FirePro D700). The model is 6.70 GiB and one
card has 6 GB, so a single device cannot hold it; the split is load-bearing, not decorative.

### End-to-end

`llama-server` with the app's environment, `-c 4096`, then two chat completions:

- prompt 74 tokens: prefill 7.71 tok/s, generation 6.17 tok/s
- prompt 74 tokens, asking for the final answer only: **6.16 tok/s**, `finish_reason: stop`

The answer was on-topic, correct about the split budget, and three sentences as asked. First
response returned empty `content` with the reasoning in `reasoning_content` — that is the
`qwen35` reasoning template, not a fault; the model needs to be told to skip reasoning to emit
a final answer. Both GPUs' `wave64 mode` and `aligned mat-vec` came up, so the GCN paths the
timestep patch protects are live in this configuration.

## Comments

- 2026-10-02: the acceptance run first failed outright with `TOSH_MGPU_EVENTS=1`. That
  turned out to be a separate defect — see ticket 10.
- 2026-10-02: `--split-mode tensor` cannot run this model at all, on either event setting:
  `GGML_ASSERT(split_state.ne[j] % div == 0)` at `ggml-backend-meta.cpp:1224`. The `qwen35`
  SSM tensors have a dimension the two-way tensor split cannot divide evenly. So the layer
  split is the only option for this model, which is what makes ticket 10's gating load-bearing.
