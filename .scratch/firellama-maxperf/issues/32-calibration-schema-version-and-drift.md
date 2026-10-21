# 32: the CSV is versioned, and its sigma drift is detectable

Status: resolved
Blocked by: none
Spec: ../spec.md

## Problem

The calibration CSV is the gate denominator and carries no version. A format change
can be read as a measurement change, and a measurement change is invisible while the
verdict happens to stay the same.

## Change

The CSV carries a schema version the gate must recognise; an unknown version is
refused rather than parsed. Drift is the ratio of a freshly measured per-cell sigma
to the recorded one, and it alarms past a stated threshold independently of the fit
verdict.

## Evidence

A perturbed copy of the real CSV raises the drift alarm while the verdict is
unchanged. An unknown version exits with the refusal path.
