# Spec: a calibration that can support a leverage analysis, and the LDS ceiling

Status: ready-for-agent (revised)

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

## Revisions

The following supersede the corresponding statements above. Each is the result of
implementing a ticket, not of reconsidering.

**The device index in the LDS measurement was wrong.** The spec said device index 2.
`MTLCopyAllDevices` returns exactly two devices on this machine, indices 0 and 1,
both FirePro D700. `GGML_METAL_DEVICES=2` registers two virtual slots mapping to
those two physical devices; it does not create a third. The measurement runs on 0
or 1, which are the same hardware.

**The refused kernel's threadgroup request is not obtainable, and does not need to
be.** Metal exposes a pipeline's static threadgroup bytes only through a built
pipeline state, and a refused pipeline has no state; every other size API is a
later macOS. The probe therefore prints `unavailable` for the refused variant rather
than inventing a number. It did find the measurement that matters: the `_lds32`
twin of the same kernel **builds** and requests **17152 bytes** against the 32768
ceiling, with the plain `_w64` and `_w64_wg32` variants refused. The open question
is therefore not "reduce the memory", since a working variant is already under the
ceiling, but **why the selector chooses a variant that does not build.**

**The gate takes exactly one noise floor.** `--calib` and `--noise-rel` are mutually
exclusive. The structural-rejection control is therefore run by widening a copy of
the calibration around each cell's mean, which scales sigma while preserving the
measured time. Under that control the gate reports `worst |z| = 0.0x`,
`reduced chi-squared = 0.0`, and still rejects on `leverage > 0.9` and
`LOO swing 41.2%`. The structural property holds.

**Calibration collection is automated, not manual.** The cell declaration, the
thermal stabilisation, the discarded warmups, the per-cell mean and sigma, and the
CSV header all belong to one script so that a rerun is a command rather than a
procedure.

**The patch series is validated in CI.** Any change to the pinned commit runs the
series checker against the pin and fails if a hunk no longer applies, so a patch
edit cannot silently break the build.

**The probe runs in CI and fails on the two false results.** It fails if any D700
reports `MTLGPUFamilyMetal3 == true`, which would be a false positive against this
machine's measured capability, and it fails if it cannot find at least one built
FA AMD variant, which is the evidence that the wave64 path exists at all.

**Ticket status.** 31, 32 and 34 are resolved. 33 and 35 are on the frontier; 36
remains blocked until 33 lands.

## Revision 2: the refusal is a selector decision, and the fifth cell is a download

**Deliverable 10 is withdrawn.** There is no layout tweak to make. Every variant that
builds requests between 10624 and 23552 bytes against a 32768 ceiling, the largest of
them 9216 bytes under, and the refused widths are exactly those carrying an `_lds32`
twin. Nothing that builds is near the ceiling, so reducing threadgroup memory would
address a constraint that is not binding.

**The refusal is a selector decision, not a memory fault.** The guard belongs at the
point where the kernel name is chosen, and the defensible form of it is: on wave64,
request the `_lds32` form first rather than requesting the plain form and falling back.
That ordering change is supported by the probe.

The stronger claim — that the plain form is never viable on GCN — is **not** proved.
Ticket 35 leaves two readings standing and they are indistinguishable from the data
available: the twin may exist *because* the plain form overflows, or the plain names may
be leftovers that were never viable. A guard that assumes the second reading would be
asserting more than the measurement supports, and it would be wrong on any hardware
where the plain form does build. The guard is therefore an ordering change, not a
prohibition, and it must remain testable by the probe. Confirming which reading holds
needs the pipelined engine run ticket 16 is still waiting for.

**The fourth-cell intermediate check has an arithmetic error in the request that
produced it.** Four cells against `p = 2` give `df = 2`, not `df = 0`; `df = 0` is the
three-cell case we already have. The intermediate check is still worth doing and is
cheap, because the 0.60 GB cell is already on disk and needs no download — but it must
be run with the minimum overridden, since the gate's own `MIN_CELLS = 5` will otherwise
report insufficiency, which is the only thing a four-cell run can say by default. What
the four-cell run buys is the leverage profile before paying for a download, not a fit.

**The fifth cell is a download, not the on-disk candidate.** `Qwen3-8B-Q4_K_M` at
4.58 GB, same quantisation family as the other four, filling the same 3.08 to 8.38 GB
bracket. This removes the size-versus-quantisation-family coupling that
`Ternary-Bonsai-2-27B-PQ2_0` would have introduced. The download is a deliberate
action on a large file and is recorded as such rather than as a side effect.

**A published five-cell pass is not guaranteed by five cells.** Leverage for a point
far from the centroid of the rest stays high however many points are added, and two of
the five additions sit at the ends of the range where leverage is naturally highest. If
five cells still reject, the leverage profile is the finding and it is reported as one.
The threshold does not move to meet the data.

**The patch series is validated in CI.** The series checker becomes a job rather than a
script someone remembers to run, so a patch edit cannot silently break the playback that
proves this tree is the pin plus a series. That provenance is load-bearing.

**The flash-attention contract is declared in a file and gated in CI.** It states the
kernel the selector requests on wave64 hardware, that the selected variant stays under
the device's threadgroup ceiling, and that the selector does not attempt a build the
probe has already refused. The third clause is the one that would have caught this, and
it is checkable: the probe already knows which names are refused, so the check is a
comparison against its output rather than a new measurement.

## Revision 3: the five cells answered the question, and the answer is the model

**The cell-count argument is settled and was right.** Five cells moved the maximum
leverage from 0.991 to 0.801 and the leave-one-out slope swing from 41.2% DOMINATED to
**8.5% ok**. No cell dominates the fit. That retires the claim that the chord was
rejected because three points cannot fit a line; it was, and now it is not.

**The verdict is still REJECT and the reason has moved.** worst |z| = 32.5, reduced
chi-squared = 774.2. The gate changed its reason rather than softening. Its output is
committed verbatim in the evidence directory.

**The residuals are curvature, not noise.** In ascending size order the signs are
`- + + - -`: below, above, above, below, on the line. Random scatter alternates signs.
A systematic sweep is what a chord through a curved relation leaves behind. Across 0.6
to 14 billion parameters, spanning four quantisations, the relation is concave: the
marginal cost per byte is roughly three times steeper at the small end than in the
middle.

**So the line-in-bytes model is misspecified, and that is a measurement.** This is the
finding the calibration was built to produce. Three cells could not separate "wrong
model" from "too few points", because they rejected on geometry and said nothing about
shape. Five cells made it definite. Adding a sixth would fail identically, so a sixth
cell is not a route.

**The decision this spec now poses, and it is exactly two options.** Both are honest
and neither touches a threshold.

*Scope the claim.* Publish a per-byte rate over the range where the marginal cost is
roughly constant, and report the small cell as a separate regime with its own number.
Narrower, bounded, defensible from the data already in hand.

*Model the shape.* Fit a form carrying a size-dependent term so the fixed cost is a
parameter rather than a residual. Better answer, more work, and it requires a
justification for the functional form that does not amount to fitting until the gate
passes.

**Deeper, not bigger.** Every ticket in this effort earns its place by removing an
ambiguity: the cell-count ticket separated geometry from noise, the probe separated
threadgroup memory from selector behaviour, the flag ticket removed an inverted
default. A ticket that adds scope without removing an ambiguity does not belong, and
neither does a sixth cell, a wider model sweep, or a second hardware target. Depth
here means one more question answered per unit of work, not more work per question.

**Loop to completion.** Each ticket states its own evidence. A ticket is done when its
stated evidence exists and can be re-run, not when the work feels finished. When a
check fails, return to the earliest ticket that could have caused it rather than
starting a new one. The effort terminates when every box is ticked, and the gate
reports what it reports — a rejection with a named cause is a completed ticket, not an
unfinished one. No threshold moves to convert a rejection into a pass.

## Revision 4: the salvage was computed from the mislabelled sigmas, and there is no rate

**The number this spec was about to publish was not approximately wrong. It was the
bug.** The proposed claim was `7.13 ± 0.21 ms/GB` with the two interior secants
"agreeing at 1.3σ". Both figures come from the sigma array that the standards review
found to be in CSV-block order rather than table order — the array that assigns 14B's
0.764 ms to 4B-Q4_K_M. Recomputing from the committed rows, with the sigmas keyed to
the cells they belong to:

| interior secant | slope | sigma |
|---|---|---|
| 2.497 → 3.306 GB | 5.84 ms/GB | ± 0.46 |
| 3.306 → 5.028 GB | 7.19 ms/GB | ± 0.21 |

They differ by 1.35 ms/GB against a combined sigma of 0.503, which is **2.68σ**. The
inverse-variance mean is **6.96 ± 0.19**, not 7.13.

Run the same arithmetic with the mislabelled array and the secants read as
`5.84 ± 1.01` and `7.19 ± 0.21`, differing by **1.31σ**, with an inverse-variance mean
of **7.14 ± 0.20**. The published pair was 1.3σ and 7.13. The mislabelling did not
merely survive into the claim; it *is* the claim, to two decimal places. That is worth
recording plainly because the failure mode is now demonstrated rather than feared: a
sigma array printed without its cell names reached a published number through a
review, a challenge, and two revisions of this spec without anyone — including the
person who wrote it — noticing.

**Correcting the mean is not enough, because the corollary forbids the average.**
`CLAUDE.md` rule 3 ends: *two probes that disagree by more than the noise floor are two
observations, not one quantity — publish what each one measured and do not average them
into a rate.* At 2.68σ these two secants disagree by more than the noise floor. The
corrected `6.96 ± 0.19` is an average of two observations that the rule says must not
be averaged. **So no rate is published for this window, corrected or otherwise.**

**What survives is two bounded statements, and they are stronger than the rate was.**
Each secant is a direct measurement over its own interval:

- **5.84 ± 0.46 ms/GB over 2.497 → 3.306 GB**
- **7.19 ± 0.21 ms/GB over 3.306 → 5.028 GB**

Published as two observations, not one quantity. And they corroborate Revision 3's
finding by an independent route: the residual signs `- + + - -` said the relation is
curved, and the secants say the same thing directly — the marginal cost is *not*
constant across the window, rising by 2.68σ between two adjacent intervals. Two
independent methods agreeing on the shape, where neither can support a single rate, is
a better result than the rate would have been.

**A rate that cannot be recomputed from the committed CSV by a committed script is a
rumour.** This is the structural fix, and it is the reason this revision exists rather
than a corrected sentence. A tool reads the calibration CSV and emits every adjacent
secant with its sigma, the chi-squared between neighbours, the inverse-variance mean
and its interval, and the explicit cell pairs used. **Its stdout is the claim.** The
number stops living in a sentence that a reader has to trust and starts being an
output anyone with the CSV can regenerate. If the script disagrees with the prose, the
script wins and the prose is rewritten. This repo has already retracted one chord for
exactly this reason, and the fix is to make the second retraction impossible.

**The window must be defended by mechanism, not by which secants agreed.** "2.50 to
5.03 GB" is currently the pair that happened to sit close together, which is the shape
of a cherry-picked window whether or not it was one. The defence is residency: show
that the cells bounding the interior intervals sit in the same VRAM-residency regime,
by comparing model size against the device working-set budget. If they do, the window
is mechanistic. If they do not, the window shrinks or the claim is withdrawn. A window
chosen because its numbers were pleasing does not become honest by being stated
carefully.

**The gate's own rejection is evidence and must be reproducible as such.** The CI
invocation runs the five committed cells and must reach REJECT with exit 1, not
argparse's exit 2. The gate output, the leverage 0.801, the 8.5% leave-one-out swing,
the worst |z| 32.5 and the reduced chi-squared 774.1 all reproduce from the CSV. The
control asymmetry is on the record and is the sharpest single result here: **widening
the sigmas flips the five-cell verdict to PASS and does not flip the three-cell
verdict.** That is what distinguishes a rejection driven by residuals from a rejection
driven by geometry, and it is why the five-cell rejection is a statement about the
model.

**The negative results are first-class artifacts, not footnotes.** Sixteen subsets with
n≥3, none passing. Three functional forms — `x²`, `ln x`, `√x` — each breaking the
leverage cap. A best quadratic still failing at reduced chi-squared 419. These are what
make the surviving claim credible, because they show the window was not selected by
exhausting the alternatives until one was quiet. They belong in the pull request body
next to the claim, not in a comment on a ticket.

**The claim ships as a file, not as a result quoted in prose.** It records the script's
stdout verbatim, the window with its residency justification, the cell count and the
coefficient of variation, the two excluded end intervals with their deltas, and the
explicit statement that this is a bounded marginal cost over a stated region — not a
bandwidth, and not a model of the full range. The end intervals are excluded because
they are more than twenty sigma away from the interior, and that exclusion is stated
in the same breath as the number rather than left for a reader to discover.

**The pull request opens now.** A fork with issues disabled does not block a pull
request; a read-only remote resolution does, and that is fixed by setting the default
repository for the fork. The draft pull request, carrying the REJECT evidence, the two
dead routes and the bounded claim, is the deliverable. Waiting for a green gate is not
required, and it would be dishonest to imply that a gate currently rejecting is
otherwise.

**Ticket 39 stays blocked, with its reason named.** The selector ordering change
becomes a change to which kernel name is requested first, and only after the engine run
shows whether the plain form fails at build time or was never viable. Those two
readings are still indistinguishable from the probe data, and an unconditional skip
would be wrong under the first. The engine run's output is the justification, and the
ticket remains blocked until it speaks.

**Deeper, not bigger, applied to this revision.** The tool, the window justification,
the claim file and the pull request each remove one ambiguity: whether the number is
real, whether the window is principled, whether the claim is stated honestly, and
whether the work is reviewable. No sixth cell, no fitted curve, no threshold moved.
The termination condition is unchanged and is not a green gate: every stated piece of
evidence exists and can be re-run.

### Decisions taken, binding on the tickets that follow

**No rate is published. Two bounded secants ship, each as its own observation.** Not
the corrected mean, and not the interval: the corollary in rule 3 is applied literally,
so `6.96 ± 0.19` is computed and *not* published as a quantity. The two statements that
ship are `5.84 ± 0.46 ms/GB over 2.497 → 3.306 GB` and `7.19 ± 0.21 ms/GB over
3.306 → 5.028 GB`.

**The script refuses to print a mean when its neighbours exceed the noise floor.** The
rule is enforced in code rather than in the judgement of whoever runs it. A script that
computes a forbidden average and leaves the decision to the reader will eventually be
read by someone who prints it. The refusal is part of the tool's contract, alongside
the secants, sigmas, neighbour chi-squared and explicit cell pairs it emits.

**The probe gains a per-device working-set budget reading, and the window stands or
falls on it.** The residency check cannot run against a quantity nothing currently
reports, so the reading is the first thing the window work needs. If the cells bounding
the interior intervals sit in the same residency regime, the window is mechanistic and
holds. If they do not, the window shrinks or is withdrawn. The probe is already the
instrument for per-device facts, so this is a new reading on an existing seam rather
than a new tool.

## Revision 5: the comparison was never run, and two claims are already upstream's

**The baseline was wrong, so the improvement has never been measured.** Every A/B in this
effort compared against stock llama.cpp. Stock llama.cpp is not the alternative a user of
this project has. The alternative is the `0.87.26` noavx2 build, and it has never been
benchmarked against this fork on this machine. Until that pairing exists, "we improved it"
is unfalsifiable: a capability claim resting on a comparison nobody ran.

**Two headline claims are retired, with citations.**

*No-AVX2 is not a differentiator.* Upstream's README states that every release also ships a
build without AVX2, and the file exists. This fork's README still tells users upstream
"needs AVX2 and dies with illegal hardware instruction". That sentence is now false, and it
is the same class of error this project refuses to let through in code.

*The D700 attention refusal was fixed upstream in 0.87.17, before us.* Their release note:
the AMD kernel asked for 34 KB of local memory and those cards give 32 KB, so it fell back to
slower kernels; a version with half the work groups now fits; reported in #12. Ticket 35
measured 33024 against 32768 and found the `_lds32` twin. **We re-derived a fix that had
already shipped.** The measurement was not wasted -- it is an independent confirmation on
this exact box -- but it is not an original contribution and will not be described as one.

**One claim survives as possibly ours, and it is unproven.** GCN matmul -- wave64 matvec,
toshgemm, bf16e emulation, aligned-load handling for pre-Vega, the Mac2 simdgroup reduction
for macOS 12/13 -- is plausibly unique to this fork. Nothing has measured it against the
right baseline.

**The README is wrong in the exact way this project catches in code.** It advertises
v0.87.14-beta.1, states a base of 0.87.23, and mentions none of the five-cell calibration,
the secants, `_lds32`, or the 0.87.26 gap. Its differentiator list is partly false. A
differentiator list is a claim, and claims here are gated.

**The sync is now urgent rather than merely cheap.** Forty-four commits to 0.87.26 touch
zero ggml-metal files, so none of the 15 patches is in their path. But a performance claim
tied to 0.87.23 is obsolete on arrival, and the 0.87.26 engine moves -- llama.cpp v0.6.0,
VRAM-reserve plumbing -- may shift the numbers by more than our patches do. Measuring first
and syncing afterwards would waste the measurement.

**Three third-party projects were assessed against the actual machine. None is a
dependency.** Strata cannot run: its macOS path is gated on Apple Silicon, unified memory and
macOS 15, and its AMD story needs 12 GB on one card against our 6. AirLLM is a per-token
whole-model PCIe stream -- on a 14B file that is over a second per token before any compute,
against the ~8.6 tok/s already measured -- and its transferable idea, expert streaming, is
what upstream Dynamic MoE already does. Colibri is the only one that runs here and the only
one worth measuring, **as an oracle rather than a dependency**: its tensor layout and quant
formats are its own, so grafting it into llama.cpp would be a rewrite, not a patch.

**The AVX1 penalty has never been measured.** Every measurement so far measured GPU paths.
The Xeon's contribution at `-ngl 0` has no number, which makes it the one hardware axis this
project has never characterised.

### Decisions taken, binding on the tickets that follow

**The baseline is the installable artifact, not a source build.** The A/B runs the 0.87.26
noavx2 build against this fork's, alternating within one session so thermal drift cancels,
same models, N at least 20. Stock llama.cpp is not a baseline for a claim about what this
fork gives a user.

**Sync before publishing.** No performance claim, README edit or release note is written
against 0.87.23. The merge lands first and the patch series must still apply cleanly against
the pin.

**Claims upstream already fixed are credited, not quietly dropped.** The D700 attention work
stays in the record with a citation to 0.87.17 and a statement that our measurement
independently confirms it on this hardware. Deleting it would be a different dishonesty from
keeping it as ours.

**Colibri is measured as an oracle and never ported.** A faster engine on the same model means
the gap is architectural and worth understanding. It does not mean adopting a second tensor
layout.

**Parity is a complete answer.** If the fork is within the noise floor of the 0.87.26
artifact, the verdict file says parity, the README says parity, and the release note says
parity. A capability claim that turns out to be a capability tie is a finished finding.

## Revision 6: the seam is the bundled engine, and both sides are artifacts

**The comparison unit is the engine binary inside the shipped bundle, not the app and not a
dev tree.** The GUI shell contributes no throughput and a great deal of nondeterminism --
MCP, telemetry, a model manager. But "the engine" cannot simply be invoked either: the app
supplies an environment and an argument vector that the A/B must reproduce, and 0.87.26
specifically repaired a VRAM-reserve value that was not reaching the engine. A binary run
with guessed flags measures a configuration nobody ships.

The method is therefore: launch the installed app once, capture the engine process's exact
argument vector and environment from the live process, and drive that same bundled binary
directly with the captured configuration, a fresh process per block. The capture is the
configuration. Anything else is an approximation of it.

**Both sides are built as bundles.** A packaged artifact measured against a development tree
is a category error: it compares a shipped configuration against an unshipped one and calls
the difference a version. Our side is built, bundled and hashed like the thing users install.

**The GUI cross-check is what makes the extraction trustworthy.** One run through the app,
comparing its own reported throughput against the band from the extracted binary. If they
disagree, the extraction is wrong -- not the engine. Without that check, a mis-captured
argument vector would produce a confident number describing a configuration that does not
exist.

**The 0.6B cell is a smoke test and is not a verdict cell.** It was the worst-fitting point in
the entire calibration at -27.8 sigma, and it sits in a different residency regime from
everything else. Its job is to prove the pipeline runs end to end before the expensive cells
run. The verdict is taken on 8B and 14B.

**The no-AVX2 property is proven by disassembly and by execution, never by filename.** This
repository has already shipped a "noavx2" download that was silently compiled with AVX2 and
SIGILLed with exit 132 on exactly these Xeons. One proof is a claim; two independent proofs
are a measurement. If either fails, the baseline is invalid and nothing measured from it may
be published.

**Packaging is gated behind the verdict.** Building a package before the verdict exists means
shipping a number nobody measured. The package is produced only after wins, parity or loses is
on file, and a parity verdict produces a release note that says parity.

**The sync precedes the measurement.** Measuring 0.87.23 and syncing afterwards invalidates
the measurement, because the 0.87.26 engine moved to llama.cpp v0.6.0 and repaired the
VRAM-reserve plumbing that a VRAM-sensitive comparison depends on.

**The Colibri dual-GPU question is answered by a probe, not by a port.** Whether MoltenVK
enumerates both D700s is a five-minute check. If it enumerates one, "Colibri can use our dual
GPU" is answered NO and no porting work begins.

### Decisions taken, binding on the tickets that follow

**Baseline capture is recorded as data, not retold as prose.** The captured argument vector,
the environment, both sha256 values, the code-signing identity and the build-version load
command are committed alongside the numbers. A reader must be able to reconstruct the
configuration without asking.

**Two sha256 values appear on every A/B row.** The extracted baseline binary and ours. A
throughput table without them cannot be attributed to artifacts.

**The verdict's primary cells are 8B and 14B.** 0.6B appears in the record as a smoke test and
is excluded from the verdict arithmetic, for the reason the calibration already established.

**A failed audit stops the work rather than qualifying it.** If the noavx2 audit fails, or the
sync breaks a patch, or the GUI cross-check disagrees with the extracted binary, the round
stops at that point. There is no partial-credit outcome in which a number from an invalid
configuration is published with an asterisk.

## Revision 7: the harness replaces the agent, and checks must be able to fail

**The measurement path must not contain an agent.** Three implementer runs died with zero
commits on this work -- two on the baseline capture, one on the sync. The measurement does not
need judgement; it needs a script that runs the A/B, writes its results to disk, and can be
re-run verbatim. The agent then reads the JSON. That is one file and it removes the failure mode
that has cost three rounds. Everything downstream cites the script's output and nothing cites an
agent's account of it.

**A check whose output is a zero must first be shown tripping on a known-bad input.** This
effort has produced three checks that could not fail: a sigma array printed without cell names
that put 14B's noise on 4B and reached a published number; an AVX2 grep that passes a 192-byte
shell script; and a metal-file count whose `fatal: bad revision` was redirected to `/dev/null`,
counted as zero, and reported as a measurement. Prose rules have failed three times, so this
becomes code: a small assertion helper that takes a check and a known-bad input and refuses to
emit a verdict unless the bad input trips it. A check that has never failed is not evidence.

**Capture argv from a structured source, never from a process environment.** `ps eww` prints
everything a process inherited, which for a launchd job includes credential material; it was
rejected by the secret scanner for exactly that reason. A launchd job's argument vector is
stored verbatim in its plist, with no environment attached. The plist is the authoritative
record; a process listing is a snapshot of whatever happened to be inherited. Where a live
process must be read, `ps -ww -o command=` gives the argument vector alone.

**A respawning process is a measurement hazard, not an inconvenience.** The CPU-only 14B server
on this machine is launchd job `com.user.llama-server`. Killing the process appeared to work and
a byte-identical replacement appeared within seconds, because that is what launchd does. Twelve
threads of CPU work at `-ngl 0` would have silently contaminated an A/B whose blocks alternate
over twenty repetitions -- the contamination would be indistinguishable from variance. The job
must be deregistered, not killed, and the check that it is gone must be `launchctl print`
failing rather than a process listing succeeding.

**The GUI is off the measurement path.** An application that will not stay dead cannot witness a
measurement. The baseline is extracted from the disk image, not from the installed copy, and run
with the argument vector the plist records. The comparison against the app's own reported
throughput is **owed** -- a line to be written once the release exists -- and not a blocker.

**An outside reviewer reaching the same conclusion is corroboration, not duplication.** A
review found that the existing calibration harness cannot produce this A/B: it measures one
binary sequentially, discards warmups as invocation counts rather than tokens, and shells out to
a benchmark tool that is not the engine under measurement. That is the same conclusion reached
here from first principles, and it is worth more for having been reached twice.

### Decisions taken, binding on the tickets that follow

**The graph is frozen at nine tickets.** Three consecutive rounds each added three or more. The
next round adds none. Work that does not fit an existing ticket is reported, not ticketed.

**The harness is a script and its output is the verdict's only permitted evidence.** Alternating
blocks, a fresh process per block, two hundred warmup tokens discarded as tokens rather than
invocations, five hundred measured, both hashes in the header, thermal state recorded per block.
No number from the older harness may be cited as verdict evidence.

**The positive control gates the audit.** The AVX2 check must run against a binary known to
contain AVX2 and see a non-zero hit before it may report zero for ours. The build tree on this
machine is real and contains genuine artifacts; locating one is part of the ticket.

**A secret-bearing capture is deleted, not redacted.** A redacted derivative of a file that
never needed to exist is worse than the file that does. Argument vectors come from the plist.

**One patch edit carries its own proof.** Any change under the patch tree must be accompanied by
the series check exiting zero in the same commit, not a follow-up.

## Revision 8: the 35B is the spine, the second D700 has a two-command answer, and a kernel that fails to build must fall back loudly

**The tiering preset is already working, and the 35B is the case it was built for.**
`ornith-1.0-35b-Q6_K.gguf` is 27 GB with 3B active per token. It runs here with about 4.4 GB
on one D700 and the rest in the 64 GB. That run is now the spine: every later cell is a delta
against it, measured the same way, and a number without its before is not a result.

**The second D700 has a two-command answer before it has a code answer.** Run `-ts 1,1` first.
If the second card stays cold, run the `MTLCopyAllDevices` probe and read the vendor patch. The
outcome is one of three and only three: the budget arithmetic, the enumeration, or a vendor
patch that pins device 0. A hypothesis about device B is not a finding until one of those says
which.

**Stop chasing the linker. Make the failure non-fatal.** A kernel the driver refuses to build
must fall back loudly, not vanish: one warning that names the fallback, and a non-vector path
where there is no twin. The dk128/dk256 layout fix is a separate ticket with its own measured
payoff, and it does not block the release.

**Speculative decoding is gated on the second GPU.** The draft runs on B and the target on A,
which is Strata's architecture. If the second device does not materialise, the ticket closes
with the measured loss on one device instead of a claim about a machine that does not exist.

**The 64 GB claim needs a pagein row.** Flat means "zero re-faults". Climbing means "expert
streaming from SSD". The row states which, with the number and the window it was taken in.

### The tasks

1. **T1, baseline the 35B.** Q6_K, `-ngl 99`, default split. Record prompt-eval and decode
   tok/s with n >= 5, a utilisation card sampled mid-decode, and a `vm_stat` pagein delta
   across a warm run. Every later cell is a delta against this.
2. **T2, settle device B with two commands, then a probe.** `-ts 1,1`; if B stays cold, the
   `MTLCopyAllDevices` probe; then the vendor patch. The outcome is one of: budget arithmetic,
   enumeration, or a vendor patch that pins device 0.
3. **T3, the flash-attention fallback.** A nil pipeline means `use_vec = false`, one warning,
   and the non-vector path. Re-run T1: the caveat disappears. The dk128/dk256 layout fix
   becomes a separate ticket with a measured payoff and must not block the release.
4. **T4, the placement matrix on the 35B.** `--n-cpu-moe {16,24,32}`, `-cmoe`, one `-ot`
   regex for the late-layer expert FFNs, `-ts 1,1`, `-sm tensor`. Every cell reports tok/s and
   both devices. A cell with one device is recorded as one device.
5. **T5, speculative decoding, only if T2 produced a second device.** The draft on B, the
   target on A, `--spec-type draft-simple --spec-draft-n-max 8`. If T2 fails, the ticket
   closes with "gated on dual-device; measured 3.5x loss on one device".
6. **T6, fidelity of this binary.** Temperature 0, fixed prompts, compared against the shipped
   build. No release without this row.
7. **T7, upstream and release.** Weekly tag check, merge the newest tag with two parents, 39
   of 39 patches, `assert_artifact()`, `make dmg`, sha256, a GPG-signed tag, the evidence
   attached. The README is written last, one sentence per CSV row, with the retractions
   listed.

### Definition of done

- The 35B number is the spine, and every optimisation carries a before and an after against
  it.
- A hypothesis about device B is not a finding until `-ts 1,1` or the probe says which.
- A kernel that fails to build falls back loudly, not silently.
- Every README claim cites a row in the evidence, and every retired claim stays visible.
- The release is signed, its digest is published, and the artifact is the one that was
  measured.

### Decisions taken, binding on the tickets that follow

**The 35B baseline is one device until a cell says otherwise.** The Metal backend registers
one device unless it is told otherwise, so every placement cell run so far, in this project
and in the record, was a one-device cell. A cell that names a second device without holding
VRAM on it is recorded as one device.

**The flash-attention refusal is a device fact, not a build defect.** The 64-lane kernel asks
for about 33 KB of threadgroup memory and a GCN 1.0 threadgroup gets 32 KB. The half-size
twin builds and runs, so the kernel is not missing, and the record that said it was is
retracted rather than edited away.

**The gate counts drops, not refusals.** A refusal the host recovers from is not a failure,
and a gate that counts it fails every good build. The gate counts a kernel with no fallback
and proves it can fail on a forced drop.

**One patch edit carries its own proof.** The series check exits zero in the same commit as
the patch, and the round trip is verified: the series applied to a fresh tree at the pin
produces the tree that was built and measured.

## Revision 8 outcome: what shipped, and the one thing that did not

The 0.87.27-beta.1 release is published at
<https://github.com/SamerKharboush/toshllm/releases/tag/v0.87.27-beta.1> with the DMG
(`sha256 3b5f41b9cdf948ba3634c31da8159a88ac9cc742193d7ee101f9f6588d4b1d3b`), the
checksums and the notes. The engine in it is the one the rows were measured on:
`assert_artifact` reads the pin `d81235049` from its `--version` and `0.87.27-beta.1`
from the bundle, and the gate passes on it with the forced-drop control reading 1.

**The release is not signed.** gpg is not installed on this machine, the only SSH key is
passphrase-protected with an empty agent, and `git tag -s` failed with "incorrect
passphrase supplied to decrypt private key". The tag is annotated, like every earlier
release tag in this fork, and the gap is written in the CHANGELOG's 0.87.27-beta.1
section, in the release notes, in the README and in ticket 64. The definition of done
above says "the release is signed"; that clause is not met, and it is named rather than
quietly dropped.

Two other clauses of the definition of done did not hold, and both are named in the
records rather than edited away:

- **"Every README claim cites a row in the evidence."** It does, for the rows R1 to R23
  that are in the CSV, and the README says which file they come from. The rows in
  `docs/bench-baseline-2026-09-30.md` are cited by that file's name, since they were
  measured before this round's CSV existed.
- **"A hypothesis about device B is not a finding until `-ts 1,1` or the probe says
  which."** It was obeyed, and it was worth the time it took: the second D700 is not
  enrolled by default, `GGML_METAL_DEVICES=2` with `GGML_METAL_DEVICE_LIST=0,1` is what
  enrolls it, and the 3.03x on the 35B decode is a measurement of that cell and not of
  a flag.

The two placements that were measured and are not what the plan expected are the two
findings of this round: a 35B MoE and a 27B dense Q8_0 both belong on the host on this
machine, and the cells that put part of the model on the card answer with zeros.
