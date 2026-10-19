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

`docs/claim-marginal-cost-2026-10-19.md`. The tool's stdout is pasted verbatim and
verified to match a fresh run byte for byte, so a reader with the CSV and
`tools/secant.py` reproduces every figure rather than trusting a transcription.

The two secants ship as two observations over their own intervals. The file states in
one sentence that their mean is refused by rule 3's corollary and carries no averaged
rate anywhere.

The window's two justifications are kept apart, as ticket 42 found them: residency
excludes the upper end because the 14B cell needs 139.7% of a 6442450944-byte budget
and must spill, while fixed-cost dominance excludes the lower end at 25 sigma and the
file says plainly that this is not a residency argument, since that cell sits at 9.9%
of the budget and is comfortably resident.

The file carries no percentage against a modelled ideal, no rate form, and no instance
of the withdrawn `7.13 +/- 0.21`.
