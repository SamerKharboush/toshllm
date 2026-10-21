# 38: the flash-attention contract is declared and gated

Status: resolved
Blocked by: none
Spec: ../spec.md (Revision 2)

## Problem

Nothing in the tree states which FA AMD kernel the selector should request on wave64
hardware, or that a build the probe has already refused should not be attempted. That
omission is why the plain-form refusal went unnoticed for so long.

## Change

A declared contract stating three things: the kernel the selector requests on wave64,
that the selected variant stays under the device threadgroup ceiling, and that the
selector does not attempt a build the probe has already refused. A check in CI
enforces the third clause by comparing against the probes refused list, which is a
comparison against existing output rather than a new measurement.

## Evidence

The contract file exists and the CI check passes on the current tree. The check must
be able to fail: demonstrate it failing when the refused list is seeded with a name
the selector does request. Do not assert a byte count the probe cannot produce for a
refused pipeline; that measurement is unobtainable by design.

## Answer

`specs/metal-fa-contract.md` declares the three clauses: (a) the wave64 vec kernel the
selector requests, its `_wg32` form and its `_lds32` twin; (b) that every variant measured as
building is between 10624 and 23552 bytes against the 32768 ceiling, with no byte count
asserted for a refused pipeline; (c) that no refused build is a dead end, which is what the
check enforces. Clause (c) is scoped to this device through the refusal record, so it is not
a prohibition on the plain form; the ordering change stays ticket 39, blocked on the engine
run.

`tools/check-fa-amd-contract.sh` compares the names the tracked series can construct against
the refusal record in the contract and exits 1 on a dead end. Run from the `fa-amd-contract`
job in `.github/workflows/build.yml`. `FA_REFUSED_EXTRA` seeds refusals, which is the failure
control: seeding `..._dk128_kf16_vf16_w64_lds32` turns the check red.
