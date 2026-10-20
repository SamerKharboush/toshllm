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

The knee is at **8 threads** on a 12-core Xeon E5-2697 v2, so the CPU lane was already
measured at the optimum and its 5.7% ratio is not retroactively disqualified.

```
-t  4: 19.55 pp tok/s  sd 0.40
-t  6: 20.28 pp tok/s  sd 0.02
-t  8: 20.49 pp tok/s  sd 0.05   <- knee
-t 12: 19.39 pp tok/s  sd 0.08
-t 16: 18.30 pp tok/s  sd 0.03
-t 24: 15.98 pp tok/s  sd 0.06
```

Going past the physical core count makes it worse, sharply so at 24 threads, so the curve has
a real knee rather than a plateau.

One thing this did surface: the sweep measured `-t 8` on this branch at **20.49** pp tok/s,
while the CPU lane measured the same binary at the same thread count at **19.68** -- a 4.1%
difference between two sessions with within-run sd under 0.1. So the absolute CPU numbers are
not reproducible across sessions to better than about 4%. The CPU lane's *ratio* was measured
side by side in one session and is the trustworthy part; the absolute values are not.
