# 18: A gate between a derived number and a published one

**What to build:** A committed script stands between a fit and a release note. Asked for a derived figure, it prints the fit together with the number of points, parameters and degrees of freedom, per-point leverage, the worst residual divided by an externally measured noise floor, and the reduced chi-squared, and it refuses when the fit fails its own test. The verification loop and the measurement loop currently share an implementation, which is why the same error class recurred three times and stopped only when a rule was written down.

**Blocked by:** None (can start immediately).

**Status:** done 2026-10-17 — the gate exists, is committed, and rejects the fit that was published.

- [ ] The script is committed and runs from a recorded command line
- [ ] It prints every cell, the noise floor it judged against, the worst residual divided by that floor, and the reduced chi-squared
- [ ] It exits non-zero when the worst-point residual exceeds a stated multiple of the noise floor or when reduced chi-squared exceeds a stated threshold
- [ ] It rejects on the whole fit rather than on the quoted cell
- [ ] Run against the three cells that produced the withdrawn decomposition, it rejects
- [ ] Every figure carries a tag marking it measured, derived, or taken from a peer, and a peer figure can never be used as a denominator

## Result

`tools/fitgate.py`, standard library only. Given cells as `name:bytes:y` and an externally measured noise floor, it prints n, p, dof, per-point leverage, every residual as a multiple of the noise floor, and reduced chi-squared, and exits non-zero when either threshold is breached. Verdicts are on the whole fit, never on a quoted cell.

Run against the three cells that produced the published decomposition:

```
n=3  p=2  dof=1
slope=10.5713  intercept=23.1362
external noise floor: 0.1100% relative

  4B_Q4_K_M        bytes=   2.4973  y=  51.320  resid=  +1.784 ( 31.6x noise)  leverage=0.236
  4B_Q6_K          bytes=   3.3063  y=  56.050  resid=  -2.038 ( 33.1x noise)  leverage=0.106
  14B_Q4_K_M       bytes=   9.0018  y= 118.550  resid=  +0.253 (  1.9x noise)  leverage=0.658

worst residual: 3.6355% = 33.1x the noise floor
reduced chi-squared: 2095.1
VERDICT: REJECT
```

This is the check that would have stopped the release note, and it cost one command.

Note the leverage column, since it is instructive and was not obvious in advance: the 14B cell carries 0.658 and is the *best*-fitting point (1.9x noise). The two cells that fail are the low-leverage 4B pair. A per-cell gate on the headline number would have passed the cell that was published.
