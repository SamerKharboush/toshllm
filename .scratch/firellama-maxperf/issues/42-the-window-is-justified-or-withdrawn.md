# 42: the window is justified by residency or it is withdrawn

Status: resolved
Type: task
Blocked by: 41
Spec: ../spec.md (Revision 4)

## Problem

Revision 4 ships two bounded secants rather than a rate, and bounds them at 2.497 to
3.306 GB and 3.306 to 5.028 GB. What makes those bounds principled is not that the two
secants agreed, because they do not agree -- they differ by 2.68σ. The bounds need a
mechanism, and the only one on offer is that the bounding cells sit in the same
VRAM-residency regime.

## Change

Decide the window from ticket 41's reading. If the cells bounding the interior
intervals sit in the same residency regime, the window is mechanistic and the two
secants are stated over it. If they do not, the window shrinks to whatever region the
reading does support, or the claim is withdrawn. There is no third option in which the
window is kept because the numbers were pleasing.

## Evidence

The residency comparison for the bounding cells, and the resulting window, stated as a
decision with the reading it came from. If the answer is that the window does not hold,
that is a completed ticket and the claim shrinks -- a window withdrawn with a reason is
worth more than a window kept by assertion.

## Answer, from ticket 41

Both D700s report `recommendedMaxWorkingSetSize = 6442450944` bytes, 6.00 GiB per
device. Against that budget the five cells sit at:

| cell | bytes | % of the per-device budget |
|---|---|---|
| 0.6B-Q8_0 | 639446688 | 9.9% |
| 4B-Q4_K_M | 2497258256 | 38.8% |
| 4B-Q6_K | 3306260704 | 51.3% |
| 8B-Q4_K_M | 5027783488 | 78.0% |
| 14B-Q4_K_M | 9001753376 | **139.7%** |

**The window holds, but only half of it is defended by residency, and pretending
otherwise would be the cherry-pick this ticket exists to prevent.**

The upper bound is mechanistic. The window ends at 5.028 GB, which is 78.0% of the
budget, and the interval above it runs from 78.0% to 139.7%. The 14B cell does not fit
in one device's working set at all; it must spill to host memory, which is a different
residency regime with a different cost structure. That regime change is exactly where
the excluded upper interval sits, so the exclusion is mechanistically justified and the
`>20 sigma` delta from the interior is a consequence of it rather than the reason for
excluding it.

The lower bound is not defended by residency. The 0.6B cell sits at 9.9% of the budget,
comfortably inside it, so residency cannot exclude that end. What excludes it is
fixed-cost dominance, and the secants measure it directly: `18.02 +/- 0.16 ms/GB` below
2.497 GB against `5.84 +/- 0.46` above it, a difference of 25 sigma. The fixed overhead
that the per-byte slope cannot absorb is concentrated in that interval, which is the
same curvature the residuals found.

So the window is published as `2.497 -> 5.028 GB`, defended by two different mechanisms
stated separately: the upper bound by the device's residency limit, the lower by
fixed-cost dominance. A single "residency regime" story covering both ends would be
false about the lower one.

The window does not shrink and the claim is not withdrawn.
