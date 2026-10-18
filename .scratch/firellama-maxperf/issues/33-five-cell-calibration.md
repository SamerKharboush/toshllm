# 33: calibrate at least five cells

Status: ready-for-agent
Blocked by: none
Spec: ../spec.md

## Problem

The existing three cells cannot spread leverage. Cells must span the parameter-size
axis so that no single point dominates the fit.

## Change

Add at least two cells to the existing 2.49 GB, 3.31 GB and 9.00 GB points. The
useful additions are one below 2.49 GB and one between 3.31 and 9.00 GB. Each cell
is measured 20 times at stabilised thermal state, pp512 and tg128, three warmups
discarded, and the tensor split stated explicitly in extra_args, because omitting it
silently measures a layer split instead and that already voided one run.

## Evidence

Per-cell mean, sigma and CV, plus confirmation from the run output that the measured
split matches the requested one. Method line states engine, pin, model, quant,
context, batch, N, warmup policy.
