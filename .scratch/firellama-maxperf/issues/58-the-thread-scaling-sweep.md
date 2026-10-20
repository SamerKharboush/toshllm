# 58: the thread scaling sweep

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The CPU lane ran at `-t 8` on a **12-core** Xeon E5-2697 v2. The 5.7% packaging number is a
ratio between two builds measured identically, so it stands, but the absolute numbers were
never taken at the knee, and "thread scaling usually saturates around physical cores" is not a
measurement.

## Change

`-t {4,6,8,12,16,24}` at `-ngl 0`, 8B-Q4_K_M, 5 repeats per cell. Report the curve, not the
best point.

## Done when

- The curve has an actual knee, and the knee's thread count is stated next to the CPU lane's
  numbers.
- If the knee is above 8, the CPU lane's absolute numbers are re-taken at the knee and the
  5.7% figure is recomputed from those.

## Answer

