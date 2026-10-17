# 19: Our own bandwidth denominator

**What to build:** The card's streaming rate is measured here rather than cited. No microbenchmark for it exists on this machine, so every decomposition attempted so far has either used a spec-sheet number or a fit slope as a stand-in. A measurement whose only work is reading bytes gives the one number the question has been missing.

**Blocked by:** 14.

**Status:** ready-for-agent

- [ ] A read-only kernel streams a buffer much larger than cache, for long enough to be at steady state
- [ ] The measured rate is reported with the buffer size, the soak duration and the number of repetitions
- [ ] The result is reported as this machine's measured rate, with no external figure quoted alongside it as corroboration
- [ ] Whether the rate is limited by the kernel or by the card is stated, and the evidence for the answer is named
