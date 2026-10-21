# The abort is split-mode-specific, and the "baseline" is not free of GCN work

Two results from isolating the preflight failure. The first answers the question that was
asked. The second questions the premise the question rested on.

## 1. The abort is the split-mode flag, not offload

Identical binary, identical model, one flag changed at a time:

| invocation | result |
|---|---|
| `-ngl 0` | SERVED |
| `-ngl 99` | **SERVED** |
| `-ngl 99 -sm layer` | **SERVED** |
| `-ngl 99 -sm tensor` | **FAILED, exit 134 (SIGABRT)** |
| `-ngl 99 -sm row` | **FAILED, exit 1** |

**Reading A was wrong: the shipped build can offload.** `-ngl 99` alone serves. What it
cannot do is tensor split -- and tensor split across two unbridged D700s is precisely the
configuration this fork exists to support.

That is a capability difference, and a much sharper one than "cannot use the GPU". It is
also testable in both directions, which "cannot offload" was not.

The preflight's earlier failure was therefore correct and its cause is now named: the
harness hardcoded `-sm tensor` in every invocation, so it asked the baseline for the one
configuration the baseline does not have.

## 2. The baseline binary already contains GCN work

String scan of the engine inside the 0.87.26 DMG:

| marker | baseline | ours | in our patch series |
|---|---|---|---|
| `wave64` | **45** | -- | -- |
| `TOSH_MV_ALIGN` | **3** | **3** | 3 patch files |
| `TOSH_FA_AMD` | **7** | (deleted, ours is `_DISABLE`) | -- |
| `TOSH_MGPU_NOWAIT` | 2 | -- | -- |
| `toshgemm` | 0 | -- | -- |

The baseline is not a build without GCN support. It carries wave64 references, it carries
`TOSH_MV_ALIGN` in the same count as ours, and it carries the older `TOSH_FA_AMD` flag that
this fork replaced with `TOSH_FA_AMD_DISABLE`.

**Consequence: "wave64 is ours" is not established by this evidence and must not be
claimed.** Either upstream implemented it independently, or the two trees share lineage
this audit cannot distinguish. The only differentiator this scan supports is the tensor-split
one above, and even that needs to be confirmed across more than one model and more than one
run before it is published.

The two binaries are not identical -- 26,466,352 versus 27,028,544 bytes -- so they are
different builds, just not different in the way the round assumed.

## What this does not establish

`amdgpu_gfx600` appears in the runtime log but is not found by `strings`, so the log line and
the string table disagree and one of those instruments is wrong. Until that is resolved, the
kernel-selection story is a report rather than a fact.

## Consequence for the round

The A/B as specified -- both sides at `-sm tensor` -- cannot run, because one side aborts.
The comparison that can run is `-ngl 99 -sm layer` against `-ngl 99 -sm layer`, plus a
separate statement that tensor split serves on this fork and aborts on the shipped build.
Those are two claims of different kinds and the verdict file must keep them apart.
