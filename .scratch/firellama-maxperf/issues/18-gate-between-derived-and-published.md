# 18: A gate between a derived number and a published one

**What to build:** A committed script stands between a fit and a release note. Asked for a derived figure, it prints the fit together with the number of points, parameters and degrees of freedom, per-point leverage, the worst residual divided by an externally measured noise floor, and the reduced chi-squared, and it refuses when the fit fails its own test. The verification loop and the measurement loop currently share an implementation, which is why the same error class recurred three times and stopped only when a rule was written down.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The script is committed and runs from a recorded command line
- [ ] It prints every cell, the noise floor it judged against, the worst residual divided by that floor, and the reduced chi-squared
- [ ] It exits non-zero when the worst-point residual exceeds a stated multiple of the noise floor or when reduced chi-squared exceeds a stated threshold
- [ ] It rejects on the whole fit rather than on the quoted cell
- [ ] Run against the three cells that produced the withdrawn decomposition, it rejects
- [ ] Every figure carries a tag marking it measured, derived, or taken from a peer, and a peer figure can never be used as a denominator
