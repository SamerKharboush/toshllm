# 10 — TOSH_MGPU_EVENTS deadlocks a layer split above a token threshold

Status: resolved (app gate + engine fix)
Type: bug

## Question

Why did the 27B acceptance run fail with `res = -3` and no diagnostic, while every other
measurement in this repo passed?

## Answer

**The shared-event cross-device hand-off deadlocks on a layer split once the prompt gets long
enough. It is not inert there — the comment it shipped with was wrong.**

### What the user saw

`llama-bench` printed exactly two lines and nothing else:

```
test_prompt: failed to decode prompt batch, res = -3
llama_bench: error: failed to run prompt
```

`res = -3` is `GGML_STATUS_FAILED` (`llama-context.cpp:2121`). No Metal error was logged at
`llama-bench`'s default verbosity.

### The real error

Reproduced through `llama-server` (which honours `-lv 5`) with a ~400-token prompt:

```
E ggml_metal_synchronize: error: command buffer 1 failed with status 5
E error: Caused GPU Timeout Error (00000002:kIOAccelCommandBufferCallbackErrorTimeout)
```

Metal command buffer status 5 is `MTLCommandBufferStatusError`. So the hand-off waits for an
event the other card never signals: a genuine cross-device deadlock, surfaced as a GPU
watchdog timeout rather than an error return.

### Threshold, measured

Layer split, `GGML_METAL_DEVICE_LIST=0,1`, `-fa 1`, 12 threads:

| model | last passing p | first failing p |
| --- | --- | --- |
| Qwen3-14B-Q4_K_M | 256 (29.45 t/s) | 257 |
| Ternary-Bonsai-2-27B-PQ2_0 | 128 (15.67 t/s) | 129 |

Qwen3-4B-Q6_K passes at p=512. The threshold is not a fixed constant — it moves with the model,
so it is a property of the hand-off size against the linked staging buffers
(`ggml_metal_xdev_link_reserve`, `ggml-metal-context.m:1987`), not a token cap.

Failing runs stall after exactly two event hand-offs (`TOSH_XDEV events=2`) against seven in a
passing run, which fits: the deadlock is reached on the third cross-device copy.

### Split-mode dependence

14B, p=512, events on:

| split mode | result | xdev tally |
| --- | --- | --- |
| layer | `res = -3` | events=2 |
| tensor | pp 43.07, tg 8.55 | events=316 |

The tensor split survives because it hand-offs 316 times instead of 7 and keeps both cards
busy; the layer split has long idle stretches where the pair can deadlock on a single
signalled event.

### The change

`Sources/Servers/Server.swift` — `TOSH_MGPU_EVENTS` is now gated on the split mode, alongside
the peer gate:

```swift
// Only a tensor split hands off activations often enough to matter, and on a
// layer split it is not inert -- measured on a non-bridged pair (2x FirePro D700):
// at 14B the shared-event hand-off deadlocked the layer split at p >= 257 (Metal
// command buffer status 5, GPU Timeout Error) while the generic host staging path
// ran the same prompt at 23.1 t/s. At 27B the threshold was p >= 129. With events
// off, both models run every prompt length tested.
if mgpuEvents && isSplitting && effectiveSplitMode == "tensor" {
    env["TOSH_MGPU_EVENTS"] = "1"
}
```

The setting keeps its name, default and user toggle. It now only reaches the engine where
measurement shows it wins, and the 27B acceptance model (which cannot use a tensor split at
all — see ticket 08) gets the generic path that runs.

## Still open (engine)

The destination's GPU-side `waitForEvent:ev_ready` was encoded into a **new** command buffer,
which appends the copy behind whatever the destination already has queued — so a destination
parked on a long graph could not drain the hand-off that graph was waiting for.

Fixed in patch 0115 (ticket 11): the wait moves to the host with a bounded timeout, and a
timeout drains both queues, completes the sequence by hand, and falls back to the generic
path.

Measured on the rebuilt engine: 14B layer p=512 21.23/5.09 (was `res = -3` at `events=2`),
27B layer p=512 11.51/6.20 (was `res = -3` at p>=129), 14B p=1024 26.65. Backend suite
10701/10701.

The app gate still stands: events are a wash on a layer split (21.24 vs 21.29 at p=512), so
they are still only set on a tensor split. What changed is that forcing them on no longer
kills the run.

## Comments

- 2026-10-02: found while running ticket 08. Threshold bisected for two models; app gate
  applied; engine defect recorded above.
