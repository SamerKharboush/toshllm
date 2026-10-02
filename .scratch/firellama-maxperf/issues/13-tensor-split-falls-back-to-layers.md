# 13 — Tensor split on an undividable model falls back to layers

Status: resolved (measured)
Type: bug

## Question

A user hit `GGML_ASSERT(split_state.ne[j] % div == 0) failed` on the 27B
with `--split-mode tensor`, after the weights had already loaded. Ticket 04
closed that as an architectural limit and left the abort in place. The limit
is real, but the abort is not the right way to express it: it fires deep in
the allocator with a backtrace, so it reads as a crash rather than a setting
the user can change.

## Answer

**The engine now reports it and exits 86. The app catches 86 and retries once
with layers.**

### Engine (patch 0128)

`ggml-backend-meta.cpp` no longer aborts on the divisibility check. It prints
the operation, the source dimension and the destination dimension, states
plainly that no two-way tensor split exists, and exits 86:

```
ggml_backend_meta: RESHAPE cannot be tensor-split: src 0 ne[0]=6144 x ratio 1
does not divide ne[0]=9216 (axis 2)
This model has no two-way tensor split. Restart with --split-mode layer.
```

86 is deliberately distinct from SIGABRT (134) and SIGSEGV (139), so the app
can tell "this split mode cannot work for this model" apart from a real crash.
`TOSH_TENSOR_SPLIT_STRICT=1` restores the abort for anyone debugging the
scheduler.

### App

`Server.swift` handles exit 86 by setting a `retryLayerSplit` flag, consuming a
line that says it is retrying by layers, and relaunching with
`--split-mode layer`. `diagnose()` gained a matching case so the failure is
still explained if the retry also fails.

The user's split-mode **setting is not modified**. Only the arguments of the
retry launch change. So if the user later picks tensor split again for a model
that supports it, it works — the fallback is not sticky, and the choice is
re-tested on every start rather than silently overridden forever.

### Measured

Same model, same two D700s, same command:

| | before | after |
|---|---|---|
| `--split-mode tensor` | SIGABRT 134, bare assert, backtrace | exit 86, names op and dims |
| `--split-mode layer` | works | works |

Layer split, 27B PQ2_0, both D700s: listening, and a chat request answers
coherently with `finish_reason: stop` at 6.18 tok/s.

The full 123-patch series applies in order to a pristine checkout of the pinned
llama.cpp commit; 0128 reverse-applies against the vendor tree.

## Why not mark the tensor unsplittable

Ticket 04 rejected that and the reasoning still holds: the scheduler needs a
split state for a node whose sources are split, and handing it one that does
not describe the data would corrupt the result silently. Exiting with a code the
app understands keeps the failure loud and gives the user a working path, while
leaving the scheduler's contract alone.
