# 36: re-run the gate on the five-cell calibration

Status: resolved
Blocked by: 31, 32, 33
Spec: ../spec.md

## Problem

The gate has never been run against a calibration with enough degrees of freedom.

## Change

Run the gate on the new calibration. Report the verdict, the leverage profile, the
leave-one-out swing and the worst z. Keep the structural-rejection control: inflating
the noise floor must still reject, because that is what distinguishes a structural
rejection from a tight floor.

## Evidence

The literal gate output, the control result, and the verdict. R^2 may be printed as
context and is never a pass criterion. If the fit still rejects, that is a finding
and not a failure to fix by moving a threshold.

## Answer

Run on 2026-10-19 against tools/calibrate/results/calibration-5cell-2026-10-18.csv.
Literal output: ../evidence/gate-5cell-2026-10-19.txt

**The geometry problem is solved.** Five cells moved the maximum leverage from 0.991
to 0.801 and the leave-one-out slope swing from 41.2% DOMINATED to **8.5% ok**. No
single cell dominates the fit any more, and the leverage sum still equals p = 2. That
is what five cells were for, and it worked.

**The verdict is still REJECT, for a different reason.** worst |z| = 32.5 and
reduced chi-squared = 774.2. The gate now rejects on the residuals, not the geometry.

**The residuals are systematic, not random.** In cell order by size:

    0.6B-Q8_0     -5.560
    4B-Q4_K_M     +7.143
    4B-Q6_K       +2.824
    8B-Q4_K_M     -4.039
    14B-Q4_K_M    -0.368

below, above, above, below, on the line. Noise scatters signs; this does not. The
signature is curvature: a chord in bytes is the wrong shape for this data.

So the finding is that **the model is misspecified**, and this is a result rather than
a failure. The three-cell fit could not distinguish "wrong model" from "too few
points"; it rejected on geometry and said nothing about the model. Five cells
converted that ambiguity into a definite answer.

No threshold was moved, and the verdict was not softened. The two honest ways forward
are to scope the published claim to the range where the marginal cost is roughly
constant, reporting the 0.6B cell as a separate regime, or to fit a model with a
size-dependent term so the fixed cost is a parameter rather than a residual.
