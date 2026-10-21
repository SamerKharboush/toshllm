# 21: Depth at fixed width and bytes

**What to build:** The depth axis is separated from width and from bytes using a model that matches the measured 14B on width and on byte count while differing in depth. Width-scaling and constant-rate laws predict approximately no change; a depth law predicts a specific increment. Only this cell can revive depth as the carrier of the per-token remainder.

**Blocked by:** 20.

**Status:** ready-for-agent

- [ ] The prediction for each candidate law is written down before the run
- [ ] The model's header confirms depth, width and bytes against the 14B it is paired with
- [ ] The measurement uses the same protocol as every existing cell, and the method line records the pairing
- [ ] The result is reported as a refutation or a confirmation, with the intercept behaviour of each law stated
- [ ] A negative intercept implied by the winning law is reported as a defect of that law, not as a finding
