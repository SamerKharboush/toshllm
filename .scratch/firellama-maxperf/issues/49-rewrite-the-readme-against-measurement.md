# 49: rewrite the README against measurement

Status: ready-for-agent
Type: task
Blocked by: 47, 48
Spec: ../spec.md (Revision 5)

## Problem

The README advertises v0.87.14-beta.1, states a base of 0.87.23, claims upstream needs AVX2 and
dies, and mentions none of this work. Its differentiator list is partly false, which is the
failure mode this project catches in code and has now shipped in prose.

## Change

Rewrite the differentiator list against verified facts only. Delete the noavx2 claim, because
upstream ships that build every release. Credit 0.87.17 for the D700 local-memory fix and say
plainly that our measurement independently confirms it here. Keep only what the A/B measured,
state the supported base version accurately, and reference what is genuinely unique -- the GCN
matmul path -- without implying it is proven faster than anything.

## Evidence

The README diff, reviewed line by line against the release notes for 0.87.17 and 0.87.26
rather than against memory, plus the statement of what remains unique.
