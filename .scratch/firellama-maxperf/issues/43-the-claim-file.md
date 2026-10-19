# 43: the claim ships as a file, not as a sentence

Status: resolved
Type: task
Blocked by: 40, 42
Spec: ../spec.md (Revision 4)

## Problem

The number that was about to be published lived in prose and was wrong. Its correction
lives in a spec revision, which is a better place but is still prose. Neither is
recomputable by a reader who has the CSV and doubts the figure.

## Change

A claim file that carries the tool's stdout verbatim, so the published number is an
output rather than a sentence. Alongside it: the window with its residency
justification, the cell count and the coefficient of variation, the two excluded end
intervals with their deltas, and the explicit statement that this is a bounded marginal
cost over a stated region -- not a bandwidth, and not a model of the full range.

The exclusions are stated in the same breath as the number rather than left for a
reader to find. No percentage against a modelled ideal appears anywhere in the file.

## Evidence

The file, with ticket 40's stdout pasted in as the primary artifact and not
paraphrased. A reader with the committed CSV and the committed tool reproduces every
figure in it. The two secants appear as two observations, never averaged.

## Answer

`docs/claim-marginal-cost-2026-10-19.md`, merged. It carries `tools/secant.py`'s stdout
byte for byte, with the command above it and the exit status 1 beside it, so the number
is an output a reader can regenerate rather than a sentence to trust.

The file states `5.84 ± 0.46 ms/GB` over 2.497 → 3.306 GB and `7.19 ± 0.21 ms/GB` over
3.306 → 5.028 GB as two observations, each over its own interval, and says in one
sentence why the mean is not published: 2.69σ is beyond the noise floor, and rule 3's
corollary makes that pair two observations rather than one quantity. It also records
that the refusal is a branch, with the control fixture that licenses a mean.

The window is 2.497 to 5.028 GB, with ticket 42's two defences kept apart: the upper
bound by device residency (the 14B cell needs 139.7% of the 6442450944-byte per-device
budget and must spill, so 5.028 → 9.002 GB crosses a regime boundary), the lower bound
by fixed-cost dominance (18.02 ± 0.16 against 5.84 ± 0.46 ms/GB, 25.1σ apart) and
explicitly *not* by residency, since the 0.6B cell sits at 9.9% of the budget.

Also present: N = 20 with three warmups discarded per cell, the per-cell coefficients
of variation (1.10, 0.43, 0.53, 0.29, 0.65 %), the two excluded end intervals with their
deltas stated beside the number (+12.17 ms/GB, 25.1σ below; +4.91 ms/GB, 17.0σ above),
a method line naming engine, pin, models and quantisations, context, batch, N and the
warmup policy, and the explicit sentence that this is a bounded marginal cost over a
stated region rather than a bandwidth or a model of the full range.

Two corrections to earlier prose came out of writing it. The excluded upper interval is
17.0σ from the interior, not "more than twenty" as Revision 4 says; its exclusion rests
on residency, so the delta is a consequence rather than the reason, which is the one
place the spec's wording and the measurement disagree. And the residency budget that
defends the upper bound is a recorded probe reading, not a modelled denominator.
