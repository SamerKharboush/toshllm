# firellama

## Agent skills

### Issue tracker

Local markdown under `.scratch/`, one file per ticket. See `docs/agents/issue-tracker.md`.

### Triage labels

Five default roles. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.

## Performance claims

`docs/bench-baseline-2026-09-30.md` is the reference table. Two rules, both learned the hard way:

1. **Never publish a percentage against a modelled ideal.** Not "18% overhead", not "73% of the
   2x", not "27% collective tax". A denominator that is itself modelled is not a measurement, and
   two such numbers have already been retracted from this repo. Either measure the quantity
   directly and quote it, or publish a bound ("below our resolution of ~X us") and say what the
   resolution is.
2. **A control that changes nothing proves nothing.** Before reading a differential experiment,
   confirm the flag takes effect on the path actually being run. `TOSH_MGPU_NOWAIT=1` returns a
   bit-identical result on an unbridged pair because it is inert there, and that null result was
   once reported as evidence that the collective wait is free.

Never say "faster" or "speedup" for a split-mode pair. Tensor split and layer split are different
constraints, not two settings of one thing; see the split-modes section of `dist/beta24-notes.md`.
Method lines are mandatory next to any throughput figure: engine and pinned commit, model and
quantisation, context size, batch size, N, and whether warmups were discarded.

## Apple Silicon

This fork targets Intel Macs with AMD dGPUs. On an Apple Silicon Mac, read
`docs/agents/apple-silicon-handoff.md` before touching anything — it says what is already done,
what is still broken, and which gates every change must pass.
