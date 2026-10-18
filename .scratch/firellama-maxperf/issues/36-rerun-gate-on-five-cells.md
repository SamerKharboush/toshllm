# 36: re-run the gate on the five-cell calibration

Status: ready-for-agent
Blocked by: 31, 32, 33
Spec: ../spec.md

## Problem

The gate has never been run against a calibration with enough degrees of freedom.

## Change

Run the gate on the new calibration. Report the verdict, the leverage profile, the
leave-one-out swing and the worst z. Keep the structural-rejection control: inflating
the noise floor must still reject, because that is what distinguishes a structural
rejection from a tight floor.

## Evidence

The literal gate output, the control result, and the verdict. R^2 may be printed as
context and is never a pass criterion. If the fit still rejects, that is a finding
and not a failure to fix by moving a threshold.
