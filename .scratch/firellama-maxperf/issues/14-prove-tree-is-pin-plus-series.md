# 14: Prove the tree is the pin plus the series

**What to build:** One command proves or disproves that the vendored llama.cpp working tree is exactly the pinned commit with the patch series applied in order. Today that is unknown, and every build, every binary and every number measured on this machine rests on it. The freeze at 4976ff3 captured the delta; this ticket says whether the delta is the series or the series plus something nobody has looked at.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] A clean checkout at the pin forward-applies every patch of the series in numeric order, with the count and the order recorded
- [ ] The result is diffed against the frozen delta, and the diff is either empty or is written down in full as the definition of the uncommitted extra
- [ ] The finding states plainly whether the tree is the pin plus the series, and if not, what the remainder is and where it came from
- [ ] Reverse-applying the series in reverse order from the working tree lands exactly on the pin, as the independent second direction
- [ ] The build recipe that reproduces the tree is recorded, so ticket 15 does not rebuild from an unproven base
