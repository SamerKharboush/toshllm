# Spec: a calibration that can support a leverage analysis, and the LDS ceiling

Status: ready-for-agent

## Problem Statement

This project publishes throughput numbers only through a gate, and the gate now
rejects the only fit we have. The rejection is not about noise. Three calibration
cells cannot support a leverage analysis: with `p = 2` parameters and `n = 3` points,
the leverage values must sum to 2, so a single cell always carries the fit. Here the
14B cell carries 0.991 of it and the leave-one-out swing is 41.2%. Inflating the
noise floor a thousandfold does not clear the rejection, which is how we know the
geometry, not the sigma, is doing the rejecting.

The practical consequence is that no throughput claim of ours is publishable, and the
current gate would reject a perfectly good fit for the same structural reason as a bad
one. Meanwhile the underlying engine behaviour we most want to explain is unexplained:
the `dk128` flash-attention kernel reports a Metal fault at pipeline creation, and the
only public account of that fault attributes it to a threadgroup (LDS) memory request
over the 32 KB ceiling. We have never measured ours.

Separately, the calibration CSV is unversioned and lives at an ad-hoc path, so the
gate's denominator can change without anyone noticing, and the gate cannot tell a
drifted measurement from a stable one.

## Solution

Redesign the calibration so that the fit has degrees of freedom, make the gate refuse
to fit at all below the cell count it needs instead of rejecting on insufficient data,
version the calibration so its drift is detectable, and measure the threadgroup memory
the `dk128` kernel actually asks for so the flash-attention fault stops being a
reported string and becomes a number.

The user-visible outcome is that a throughput number either has a fit that survives a
leverage analysis or is not published, and that the flash-attention memory question
has an answer measured on this hardware.

## User Stories

1. As the maintainer, I want the calibration to span at least five cells before any
   fit is attempted, so that no single cell can dominate the leverage.
2. As the maintainer, I want a cell count below the minimum to be reported as
   insufficient rather than as a rejection, so that "not enough data" is not
   misreported as "bad data".
3. As the maintainer, I want cells chosen to span the parameter-size axis broadly,
   so that leverage is spread rather than concentrated at one end.
4. As the maintainer, I want the same model at two quantisations where possible, so
   that quantisation cost is separable from size cost.
5. As the maintainer, I want each cell measured 20 times at stabilized thermal state,
   so that the per-cell sigma is measured rather than assumed.
6. As the maintainer, I want warmups discarded and the policy stated, so that the
   method line is honest about what was thrown away.
7. As the maintainer, I want the per-cell sigma to come from the raw invocations
   rather than from the fit residuals, so that the gate does not grade its own
   homework.
8. As the maintainer, I want the calibration CSV to carry a schema version, so that a
   format change cannot be silently read as a measurement change.
9. As the maintainer, I want a PR that changes Metal code to re-run the calibration,
   so that a stale denominator cannot back a fresh claim.
10. As the maintainer, I want the gate to detect sigma drift beyond a stated threshold,
    so that a measurement change is visible even when the verdict does not move.
11. As the maintainer, I want the leverage sum asserted to equal the parameter count,
    so that a broken leverage computation fails loudly instead of passing quietly.
12. As the maintainer, I want the leave-one-out swing reported per cell, so that the
    dominant point is named rather than inferred.
13. As the maintainer, I want Cook's distance reported, so that a point's influence is
    visible independent of leverage.
14. As the maintainer, I want the gate to keep rejecting on structure after the noise
    floor is deliberately inflated, so that this property is tested rather than assumed.
15. As the maintainer, I want the slope printed in the units the axis is in, so that a
    real slope is never displayed as zero.
16. As the maintainer, I want the flash-attention kernel's threadgroup memory request
    measured in bytes, so that the 32 KB ceiling can be compared rather than guessed at.
17. As the maintainer, I want that measurement taken on the D700, so that it describes
    the hardware the kernel has to run on.
18. As the maintainer, I want the fault string recorded alongside the measurement, so
    that the driver's wording and our number are kept together.
19. As the maintainer, I want a layout tweak proposed only if the request exceeds the
    ceiling, so that we do not adjust a kernel that is already within its budget.
20. As the maintainer, I want flash attention to be on by default on wave64 with a
    single opt-out, so that the correct path is the default path. (Done: `14f5aee`.)
21. As the maintainer, I want the opt-out to be the only flag, so that the inverted
    presence-test semantics cannot return.
22. As the maintainer, I want the patch series verified against the pin by the repo's
    own checker, so that a patch edit is proven to still apply. (Done: exit 0.)
23. As the maintainer, I want the kernel presence check to state that presence is not
    usability, so that a shipping-but-broken kernel cannot pass silently. (Done: `0c456c3`.)
24. As the maintainer, I want the CI gate to refuse a modelled floor when the CSV is
    absent, so that a claim can never be gated against a guess. (Done: `25f8074`.)
25. As the maintainer, I want the gate's CI job to be expected red while the fit is
    bad, so that a green badge cannot be produced by weakening the gate.
26. As the maintainer, I want the external claims the gate rests on verified against
    primary sources, so that a retracted comment is not cited as definitive.
27. As the maintainer, I want corrections to my own earlier statements recorded, so
    that a wrong claim does not persist in the record.

## Implementation Decisions

- **The minimum cell count is a gate precondition, not a threshold.** Below the
  minimum the gate reports insufficient data and exits non-zero without fitting. The
  current `n = 3` case would then report insufficiency rather than a geometric
  rejection, which is the truthful description.
- **Cell selection spans the parameter-size axis.** The existing three cells cover
  2.49 GB (4B Q4_K_M), 3.31 GB (4B Q6_K) and 9.00 GB (14B Q4_K_M). At least two more
  are required; the useful additions are a small cell below 2.49 GB and one between
  3.31 and 9.00 GB, which flattens the leverage profile. Cells are declared in the
  existing three-field form (label, test, extra arguments) with the tensor split
  stated explicitly, because omitting it silently measures a layer split instead and
  that already voided one run.
- **Sigma stays measured, never modelled.** Per-cell sigma is the standard deviation
  of the raw invocations in that cell's CSV block. The gate propagates
  `y = 1000/t` to `sigma_y = (y^2/1000) * sigma_t`. If a cell has no calibration
  entry the gate refuses to run rather than substituting a uniform floor.
- **The CSV gains a schema version and a drift check.** The version is a row in the
  file, and the gate refuses a version it does not know. Drift is the ratio of a
  freshly measured sigma to the recorded one, and it alarms past the stated threshold
  independently of the fit verdict, so a measurement change surfaces even when the
  verdict is unchanged.
- **The existing structural alarms stay.** Leverage sum asserted equal to `p`, the
  leave-one-out swing, Cook's distance, worst `|z|` against the measured floor, and
  reduced chi-squared. `R^2` is printed as context and is never a pass criterion.
- **The threadgroup memory measurement is a probe, not a patch.** It reads the
  pipeline's requested threadgroup memory in bytes on device index 2 and prints it
  next to the ceiling. Any layout change is a separate decision taken only if the
  measurement exceeds the ceiling, and it must not be made speculatively.
- **The fault string is quoted, not paraphrased.** `exceed the local data storage
  limit` is a driver message, not Apple's wording; Metal's own phrasing is
  threadgroup-worded. The probe records the driver's exact string so the two are not
  conflated later.
- **The module surface is the existing one.** The gate keeps its current single entry
  point and flags; the calibration harness keeps its cell declaration file and its CSV
  output; the kernel checks keep their script form. No new module is introduced.
- **The vocabulary is the project's.** "Cell" for one model-and-test calibration
  point, "chord" for the line through the size-versus-time points, "floor" for the
  measured noise, "gate" for the publish decision, "wave64" for the AMD dispatch
  width, "LDS" only when quoting the driver.

## Testing Decisions

A good test here observes the gate's decision and its printed fields, not its
internals. The gate is the seam: it is the one place where a calibration, a set of
sigmas and a verdict meet, and everything the project publishes passes through it.
The existing seams are preferred over new ones, and no new seam is proposed.

- **The gate is tested against synthetic calibrations with known leverage profiles**,
  which is prior art in this repo: the gate already carries an assertion that the
  leverage sum equals `p`, and that assertion is the cheapest possible test of the
  leverage computation.
- **The structural-rejection property is tested by a control**, not by inspection:
  inflating the noise floor until the sigmas are meaningless must still reject. That
  control has already been run once and must keep passing, because it is what
  distinguishes a structural rejection from a tight floor.
- **Insufficiency is tested by running the gate below the minimum cell count** and
  asserting the exit is the insufficiency path rather than the rejection path.
- **The drift alarm is tested by perturbing one cell's sigma in a copy of the CSV**
  and asserting the alarm fires while the verdict is unchanged.
- **The patch series is tested by the repo's own dry-run checker against the pin**,
  which is prior art and already in use; the flag change was verified this way rather
  than by reading.
- **The kernel check is tested by its own failure modes.** It must exit non-zero on a
  missing metallib and must not report ABSENT for a present kernel, which is the bug
  it shipped with twice.
- **The threadgroup memory probe is tested by running it on the D700 and comparing
  against the ceiling**, not by asserting a constant, because the number is the
  deliverable.

## Out of Scope

- **Upstreaming anything.** No PR to llama.cpp, and the project's policy on AI-written
  prose is a constraint on any future attempt.
- **Apple Silicon.** This effort targets Intel Macs with AMD dGPUs only.
- **Vulkan.** Parked, with its reopening conditions stated elsewhere.
- **The four outstanding porting items from the external wave64 branch** (command
  buffer node budget, tool-call-id fix, divergence harnesses, narrower concurrency
  gate). They are recorded and separately decidable.
- **Bigger memory-layout work on the flash-attention kernels.** This spec measures the
  request; it does not commit to a redesign.
- **The parity result.** Already measured and accepted, with the top-1 flip tracked.

## Further Notes

- **The external branch is not independent prior art.** It shares verbatim comments,
  log strings, environment variable names, property names, function-constant slots and
  kernel names with this fork, and its own documentation points at this project's
  vendor tree. Agreement between the two is ancestor-versus-descendant and must not be
  presented as independent corroboration.
- **The kernel coverage question is closed.** The shipping metallib carries 12 DK
  widths, 24 K/V type pairs and six dispatch variants. The external branch's three-by-
  nine matrix is a strict subset, so there were no gaps to document against it.
- **Two corrections belong in the record.** Upstream permits AI-generated code with
  disclosure; what it forbids is AI-written prose and autonomous submission. And the
  issue cited as the definitive source on the reduction gate was closed as stale, with
  its key comment retracted by its own author.
- **The gate will be red in CI until this spec lands.** That is the intended state.
  A green badge obtained by relaxing the gate would be the failure mode this spec
  exists to prevent.
- **`TOSH_FA_AMD=0` used to mean on.** Any configuration still setting it explicitly
  needs to move to leaving it unset, and the only remaining flag is
  `TOSH_FA_AMD_DISABLE=1`.
