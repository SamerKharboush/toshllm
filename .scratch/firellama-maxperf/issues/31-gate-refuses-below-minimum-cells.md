# 31: the gate reports insufficiency, not rejection

Status: resolved
Blocked by: none
Spec: ../spec.md

## Problem

Three cells cannot support a leverage analysis. With p = 2 and n = 3 the leverage
values must sum to 2, so one cell always dominates: the 14B cell carries 0.991 and
the leave-one-out swing is 41.2%. The gate reports this as REJECT, which reads as
"the data is bad" when the truthful statement is "there is not enough data".

## Change

A minimum cell count becomes a precondition of the fit. Below it the gate prints the
cell count, the minimum, and an insufficiency message, and exits non-zero without
computing a slope. Above it, behaviour is unchanged.

## Evidence

Exit code and message differ between the two paths, and the insufficiency path
prints no slope. A run at the minimum still fits and can reject normally.
