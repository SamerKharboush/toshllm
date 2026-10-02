# 11 — Engine: cross-device stall, NSRange length, tensor-split diagnostic

Status: resolved (measured)
Type: bug

## Question

Ticket 10 left the engine half of the events deadlock open and listed two more engine
defects. With the app now compiling and a real build loop available, can they be fixed and
measured?

## Answer

**Two of the three fixed and measured. The third is a real architectural limit, now with a
message that says so instead of an assert.**

Patch: `patches/llama/0115-metal-xdev-stall-and-nsmakerange.patch` (5 hunks, 3 files).

## 1. Cross-device stall — fixed

`ggml_metal_cpy_xdev_events` encoded a GPU-side `waitForEvent:ev_ready` into a **new**
command buffer on the destination. That appends the copy behind whatever the destination
already has queued. When the destination is parked on a long graph which is itself waiting
on the source, the copy cannot drain, and the pair stalls until the Metal watchdog kills the
buffer — status 5, `kIOAccelCommandBufferCallbackErrorTimeout`.

Two changes:

- The destination waits on the **host**: `waitUntilSignaledValue:seq timeoutMS:…`
  (2000 ms, `TOSH_MGPU_XDEV_TIMEOUT_MS`). The copy still lands in the destination's held
  command buffer when `hold_dst`, so its queue position is unchanged in the normal case.
- On timeout, the copy reports itself and returns false, which sends it down the existing
  generic host-staging path. Because the source had already committed its blit and claimed
  the sequence, recovery also drains both queues and completes `ev_ready`/`ev_done` by hand
  — otherwise the next hand-off's `waitForEvent:ev_done` waits on a signal nobody sends.

Sequence numbers are now claimed only once the source side is committed (`link->seq = seq`
after `cmd_buf_end`), so a failed wait cannot leave a dangling sequence.

### Measured

The configs that failed before, on the rebuilt engine:

| | before | after |
|---|---|---|
| 14B layer p=512 events | `res = -3`, tally `events=2` | pp 21.23 / tg 5.09, `events=33 generic=2` |
| 27B layer p=512 events | `res = -3` at p>=129 | pp 11.51 / tg 6.20, `events=65 generic=2` |
| 14B layer p=1024 events | `res = -3` | pp 26.65, `events=33 generic=4` |

Full backend suite after the change: **10701/10701, 0 FAIL** (unchanged from before).

Speed is a wash on a layer split (14B p=512: 21.24 events vs 21.29 off; p=1024: 26.65 vs
26.54), so the app-level gate in ticket 10 still stands — events are only worth setting on a
tensor split. What changed is that forcing them on a layer split is now safe instead of fatal.

## 2. `NSMakeRange` length — fixed

`ggml-metal-device.m:3477` passed `NSMakeRange(bid_dst.offs, bid_dst.offs + size)`.
`NSRange` is `(location, length)`, so the length was the *end offset*: the fill ran `offs`
bytes past the end of the intended region. Now `NSMakeRange(bid_dst.offs, size)`.

## 3. Tensor-split assert on the 27B — diagnosed, not fixed

The bare `GGML_ASSERT(split_state.ne[j] % div == 0)` at `ggml-backend-meta.cpp:1224` now
names the op and the dimensions:

```
RESHAPE cannot be tensor-split: src 0 ne[0]=6144 x ratio 1 does not divide ne[0]=9216 (axis 2)
```

That is `qwen35.cpp:398`, the SSM state reshape
`reshape_4d(state, head_v_dim, head_v_dim, num_v_heads, n_seqs)`. The source is split along
`ne[0]=6144` but the output is not divisible by it, so no two-way tensor split of this
tensor exists.

**Not fixed, deliberately.** Marking it unsplittable would leave the scheduler with no
answer for a node that legitimately needs split data, and the only way to know whether the
scheduler degrades correctly is a build with tensor split and a numerical comparison against
a single-GPU run — which this hardware cannot host (the 27B needs both cards just to load).
The abort becomes a clear message instead; the layer split, which is what this model
actually uses, is unaffected.

## App build fixes (the two that blocked compiling at all)

- `ChatTab.swift` — `sharedBackgroundVisibility` only exists in the macOS 26 SDK, and a
  runtime `#available` is not enough: the compiler still resolves the symbol. Now guarded by
  `#if compiler(>=6.2)`, the same pattern `GlassStyle.swift` already uses.
- `VideoGenTab.swift` / `VideoGen.swift` — the detached frame decode returned
  `[NSObject]` and, once annotated `[NSImage]`, warned that a non-Sendable type crossed an
  actor boundary. `NSImage` is main-actor bound, so the decode now returns `[Data]`
  (`displayFrameData`) and the `NSImage` is built on the main actor. Both call sites fixed.

## make-app.sh

The three `metallib` guards became warnings. Precompiling them needs Xcode's `metal`
compiler, which Command Line Tools does not ship, and there is no `metal` binary anywhere on
this box. The engines already fall back to compiling their embedded sources at launch, which
every run on this machine has been doing. The binaries themselves are still bundled; only
the optional precompiled kernels are skipped.

## Not verified

- The 27B tensor split still aborts. Diagnosed, deliberately unchanged (see above).
- No numerical A/B of the `NSRange` fix against a pre-fix run: the overfill only manifests
  as a buffer overrun on a code path the local models do not exercise. The change is a
  strict narrowing of the filled range to the region the caller asked for.
