# 60: speculative decoding with a draft model

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

Strata's published 1.6-1.8x comes from a small draft model proposing and the big model
verifying. llama.cpp has the same mechanism, and this box has both models already:
`Qwen3-0.6B-Q8_0` as the draft and `Qwen3-8B-Q4_K_M` as the target. It is the one Strata idea
that needs no new code, and it is the cheapest candidate in the whole effort.

## Change

`-md qwen3-0.6b.gguf --draft-max 8 -ngl 99` on the draft, target at 8B. Report the acceptance
rate and the net tok/s, not just the ratio.

## Done when

- Acceptance rate and net tok/s on this box, next to Strata's published 1.6-1.8x, measured the
  same way and labelled as a target to reproduce rather than a figure to cite.
- The draft model's own offload settings recorded, since the draft runs on the same two D700s.

## Answer

**The draft was never firing because `--spec-type` defaults to `none`.** `-md` loads the draft
model; the speculative path stays switched off, and the engine does not complain. With
`--spec-type draft-simple --spec-draft-n-max 8` it fires:

```
I slot print_timing: draft acceptance = 0.40000 (  96 accepted /  240 generated), mean len =  4.20
```

**And it is 3.5x slower.**

| configuration | tok/s |
|---|---|
| no draft | 8.184 / 8.186 / 8.191 |
| `--spec-type draft-simple --spec-draft-n-max 8` | 2.360 / 2.366 / 2.363 |

The mechanism works and the acceptance rate is healthy; the economics are inverted, because the
0.6B draft competes with the 8B target for the one card that is already the bottleneck. Strata's
published 1.6-1.8x does not reproduce on this box, and the reason is specific: there is no
second device to draft on.

Not swept: the draft's own placement (`--spec-draft-n-cpu-moe`, `--spec-draft-n-gpu-layers`).
A CPU-resident draft is the obvious next cell.
