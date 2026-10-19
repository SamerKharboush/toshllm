# 43: the claim ships as a file, not as a sentence

Status: ready-for-agent
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
