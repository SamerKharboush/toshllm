# 42: the window is justified by residency or it is withdrawn

Status: ready-for-agent
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
