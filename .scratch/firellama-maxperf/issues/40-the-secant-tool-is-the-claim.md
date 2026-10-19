# 40: the secant tool is the claim

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 4)

## Problem

The published number lived in a sentence. It was wrong, and it was wrong because a
sigma array printed in CSV order rather than cell order was read into it and nobody
caught it through a review, a challenge, and two spec revisions. A number that cannot
be recomputed from the committed CSV by a committed script is a rumour. This repo has
already retracted one chord for exactly this reason, and the fix is to make the second
retraction impossible rather than to be more careful.

## Change

A tool that reads the calibration CSV and emits, as its stdout: every adjacent secant
with its slope and its sigma derived from the per-cell sigmas, the chi-squared between
neighbouring secants, the inverse-variance mean and its interval, and the explicit cell
pairs used. Its stdout is the published number. If it disagrees with the prose, the
tool wins and the prose is rewritten.

It must refuse to print a mean when neighbouring secants disagree beyond the noise
floor. Rule 3's corollary makes that average forbidden, and the refusal belongs in the
tool rather than in the judgement of whoever runs it: a tool that computes a forbidden
average and leaves the decision to its reader will eventually be read by someone who
prints it. The refusal is part of the contract.

## Evidence

Run it against the five-cell CSV. Expected secants, with the sigmas keyed to the cells
they belong to rather than to their position in the file:

- 0.6B → 4B-Q4_K_M: 18.02 ± 0.16 ms/GB
- 4B-Q4_K_M → 4B-Q6_K: 5.84 ± 0.46 ms/GB
- 4B-Q6_K → 8B-Q4_K_M: 7.19 ± 0.21 ms/GB
- 8B-Q4_K_M → 14B: 12.10 ± 0.20 ms/GB

The two interior secants differ by 2.68σ, so the mean must be refused with a distinct
message and a non-zero exit, not printed with a caveat. Exit codes distinguish a
refusal from a failure to read the CSV.
