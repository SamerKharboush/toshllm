# 23: Is the per-token remainder a fixed cost with a lever

**What to build:** Decode-only windows at several generation lengths, repeated across independent process starts, decide whether the per-token cost that does not scale with bytes is a fixed engine or hardware cost that responds to anything, or an artefact of how the windows were cut. Thermal state and startup cost are excluded by construction. This is the only open question whose answer changes a decision.

**Blocked by:** 15, 18.

**Status:** ready-for-agent

- [ ] Decode-only windows are measured at several generation lengths, with no prefill inside the measured window
- [ ] Each length is repeated across independent process starts, and per-start results are reported rather than pooled
- [ ] Thermal state during the runs is recorded, and any run where it moved is discarded and said to be discarded
- [ ] The finding states whether per-token cost is flat across length, and if not, what it does instead
- [ ] No lever is claimed unless a change to it produced a measured change in the same protocol
