# 20: Width at fixed depth

**What to build:** One cell tells apart three predictions that currently cannot be separated. A model with the same depth as the 4B pair and a different width produces an increment over the 4B that either matches a width-scaling law, a constant-marginal-rate law, or a depth-scaling law. The three predictions are pre-registered as disjoint bands before the run, so the result is a refutation rather than a fit.

**Blocked by:** 14, 15, 18.

**Status:** ready-for-agent

- [ ] The three predicted bands are written down before the run, with the increment that separates them
- [ ] The cell is measured on the proven build, in the same protocol as the existing cells, with the method line recorded
- [ ] The result is reported against the pre-registered bands, and the law it refutes is named
- [ ] The model's depth, width and tensor count are recorded from its header, confirming depth is genuinely held
- [ ] The run is repeated across independent process starts and the spread is reported
