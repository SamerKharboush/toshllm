# The ISA is exonerated: the patch is the cause, and "served" still is not "split"

## The decisive corner

| build | sha256 (first 8) | AVX1 mnemonics | AVX2/FMA mnemonics | runs on host |
|---|---|---|---|---|
| ours@AVX1 | `fce9e70e` | 3709 | 0 | yes |
| ours@SSE2 | `b8ef1158` | 0 | 0 | yes |

The two builds are genuinely different ISA targets, and both execute. `TOSH_NO_AVX2=1` produces
a real SSE4.2 binary, not an AVX1 one with a different name.

**`-ngl 99 -sm tensor` at 0.6B on ours@SSE2: SERVED.**

That is the corner that decides the question. Had it aborted, the baseline's crash would have
been an ISA artifact and the claim would have been packaging. It served, so:

> The abort is not the ISA. The patch is the cause. The capability difference is **code**.

## What this does not yet say (D2), and it is not a small gap

`SERVED` proves the abort is gone. It does not prove two GPUs did the work. The 0.6B log names
**one device**:

```
device 0: AMD Radeon HD - FirePro D700
```

There is no second device line and no per-device buffer allocation in the capture. A degenerate
split that places every tensor on device 0 serves perfectly and would look exactly like this.
At 0.6B everything fits on one card, so this run could not have distinguished the two cases even
in principle.

So the honest current claim is: **this branch does not abort where the shipped build does.** The
claim that it *tensor-splits across both D700s* is untested. Ticket 46 must record a served cell
with one device as *served, unsplit*, never as a pass, and the 8B and 14B runs are where the
allocation lines have to appear.

## Corners still missing

| corner | status |
|---|---|
| ours@AVX1 | built, serves |
| ours@SSE2 | built, serves |
| upstream@SSE2 | the shipped DMG, aborts |
| upstream@AVX1 | **not built** |

`upstream@AVX1` is the corner that distinguishes "the patch series does the work" from "upstream
ships a badly-tuned binary and the fork merely tunes it". Both are user-visible wins, but they
are different sentences in the release note, and only that build separates them. Until it exists,
the claim is: the patch is the cause **relative to the SSE2 baseline that was actually shipped**,
which is not the same statement as the patch being the cause in general.

## D3 landed

`scripts/build-engines.sh` now defaults `TOSH_AVX1=1` when the host lacks AVX2, and asserts after
the build that the engine both executes and scans clean. The check was validated the way this
project requires: 0 mnemonics on ours@AVX1, 3 on the AVX2 control, and the control executes with
exit 132. A check that cannot fail proves nothing, and this one has been shown failing.
