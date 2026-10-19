# The claim: marginal cost per byte of decoded tokens, 2026-10-19

Two bounded secants ship. There is no rate.

Everything below is recomputable from `tools/calibrate/results/calibration-5cell-2026-10-18.csv`
with `tools/secant.py`. Its stdout is the number; if this prose disagrees with it, the tool wins
and the prose is rewritten.

## Method line

Engine 0.87.24-beta.1, llama.cpp pinned at `d81235049384534c167caea52b85a694f6103d14` (v0.6.0)
plus the 38-patch series; `llama-bench` from that tree's `build-static`, `-sm tensor`.
Models Qwen3-0.6B-Q8_0, Qwen3-4B-Q4_K_M, Qwen3-4B-Q6_K, Qwen3-8B-Q4_K_M, Qwen3-14B-Q4_K_M at
639446688, 2497280256, 3306260704, 5027783488 and 9001753376 bytes. Test `tg128`, i.e. 128
generated tokens and no prompt. Context 128, which is what the pin's `n_ctx = n_prompt + n_gen`
yields for this test; it is not an explicit flag and is not recorded in the log, so it is read
from the binary's own source rather than from the run. Batch 2048 / ubatch 512, the pin's
defaults, no `-b` or `-ub` passed and likewise not recorded in the log. N = 20 measured
invocations per cell, each invocation `-r 2` internally. 3 warmups discarded per cell before the
measured block, 600 s idle before each cell. The per-cell sigma is the stdev across the 20
invocations, not the within-invocation stdev. Env exactly as the log records it:
`GGML_METAL_DEVICES=2`, `GGML_METAL_VRAM_RESERVE_MB=1024`,
`GGML_METAL_SIMDGROUP_REDUCTION_DISABLE=1`, `TOSH_FA_AMD=1`.

## The claim

Two observations, each over its own interval, in ms of decode time per GB of model:

| # | slope | sigma | interval | cells |
|---|---|---|---|---|
| 1 | 5.84 ms/GB | ± 0.46 | 2.497 → 3.306 GB | 4B-Q4_K_M → 4B-Q6_K |
| 2 | 7.19 ms/GB | ± 0.21 | 3.306 → 5.028 GB | 4B-Q6_K → 8B-Q4_K_M |

They are **not** averaged, and they are not to be averaged. The two differ by 1.35 ms/GB against
a combined sigma of 0.503, which is 2.69σ — more than the noise floor — and `CLAUDE.md` rule 3's
corollary says two probes that disagree by more than the noise floor are two observations, not
one quantity, so a mean across them is not a rate that may be published. `tools/secant.py`
enforces that in code: it refuses the mean, prints none, and exits 1, rather than computing it
and leaving the decision to whoever runs it. The refusal is a live branch, not a dead end —
`tools/secant-control-3cell.csv` is a control whose neighbours agree at 0.33σ and for which the
tool does print a weighted mean and exit 0.

And stated here, beside the number rather than in a footnote, the two adjacent intervals this
claim excludes:

| excluded | slope | sigma | interval | delta from the shipped secant | why |
|---|---|---|---|---|---|
| below | 18.02 ms/GB | ± 0.16 | 0.639 → 2.497 GB | +12.17 ms/GB from secant 1, 25.1σ | fixed-cost dominance |
| above | 12.10 ms/GB | ± 0.20 | 5.028 → 9.002 GB | +4.91 ms/GB from secant 2, 17.0σ | device residency |

## The tool's stdout, verbatim

The command:

```
python3 tools/secant.py --calib tools/calibrate/results/calibration-5cell-2026-10-18.csv \
    0.6B-Q8_0:639446688 4B-Q4_K_M:2497280256 4B-Q6_K:3306260704 \
    8B-Q4_K_M:5027783488 14B-Q4_K_M:9001753376
```

Its stdout, unedited, and its exit status is 1:

```
calibration tools/calibrate/results/calibration-5cell-2026-10-18.csv   test tg128
x = bytes / 1e9 (GB).  sigma = stdev of the per-invocation values, propagated to ms/token.

cells, ascending x; each sigma sits on the row of the cell it was measured on
  cell                    bytes     x_GB      y_ms  sigma_ms    n
  0.6B-Q8_0           639446688    0.639    18.191    0.2003   20
  4B-Q4_K_M          2497280256    2.497    51.662    0.2197   20
  4B-Q6_K            3306260704    3.306    56.387    0.2977   20
  8B-Q4_K_M          5027783488    5.028    68.768    0.2007   20
  14B-Q4_K_M         9001753376    9.002   116.863    0.7642   20

adjacent secants; sigma comes from the two bounds named in the row
  id  cell pair (ascending x)             from_GB    to_GB   dx_GB  slope_ms/GB   sigma  sig_from  sig_to
  s1  0.6B-Q8_0 -> 4B-Q4_K_M                0.639    2.497   1.858        18.02    0.16    0.2003  0.2197
  s2  4B-Q4_K_M -> 4B-Q6_K                  2.497    3.306   0.809         5.84    0.46    0.2197  0.2977
  s3  4B-Q6_K -> 8B-Q4_K_M                  3.306    5.028   1.722         7.19    0.21    0.2977  0.2007
  s4  8B-Q4_K_M -> 14B-Q4_K_M               5.028    9.002   3.974        12.10    0.20    0.2007  0.7642

secants as published, each over its own interval and not to be averaged
   18.02 +/- 0.16 ms/GB over 0.639 -> 2.497 GB   (0.6B-Q8_0 -> 4B-Q4_K_M)
    5.84 +/- 0.46 ms/GB over 2.497 -> 3.306 GB   (4B-Q4_K_M -> 4B-Q6_K)
    7.19 +/- 0.21 ms/GB over 3.306 -> 5.028 GB   (4B-Q6_K -> 8B-Q4_K_M)
   12.10 +/- 0.20 ms/GB over 5.028 -> 9.002 GB   (8B-Q4_K_M -> 14B-Q4_K_M)

neighbouring secants, 1 dof; they must agree within 2 sigma (chi2 <= 4.00) for a mean to be licensed
  pair       difference  combined_sigma       z     chi2   verdict
  s1 vs s2        -12.17           0.485  -25.12   631.17   DISAGREE
  s2 vs s3          1.35           0.503    2.69     7.22   DISAGREE
  s3 vs s4          4.91           0.288   17.04   290.41   DISAGREE

MEAN REFUSED: 3 of 3 neighbouring secant pairs differ by more than 2 sigma.
  s1 (18.02 over 0.6B-Q8_0 -> 4B-Q4_K_M) vs s2 (5.84 over 4B-Q4_K_M -> 4B-Q6_K): 25.12 sigma
  s2 (5.84 over 4B-Q4_K_M -> 4B-Q6_K) vs s3 (7.19 over 4B-Q6_K -> 8B-Q4_K_M): 2.69 sigma
  s3 (7.19 over 4B-Q6_K -> 8B-Q4_K_M) vs s4 (12.10 over 8B-Q4_K_M -> 14B-Q4_K_M): 17.04 sigma
  Rule 3, corollary: two probes that disagree by more than the noise floor are two
  observations, not one quantity. No weighted mean is computed or printed here.
  Publish the secants above, each over its own interval.
```

## The window is 2.497 to 5.028 GB, and it has two justifications

Not one. A single "the bounding cells sit in the same residency regime" story would be true at
the top of the window and false at the bottom, so the two ends are defended separately and
neither defence is stretched to cover the other.

**Upper bound, by residency.** Both FirePro D700s report `recommendedMaxWorkingSetSize =
6442450944` bytes, 6.00 GiB per device, as read by `tools/metal-probe/threadgroupprobe.m` on this
machine. Against that budget:

| cell | bytes | % of the per-device budget |
|---|---|---|
| 0.6B-Q8_0 | 639446688 | 9.9% |
| 4B-Q4_K_M | 2497280256 | 38.8% |
| 4B-Q6_K | 3306260704 | 51.3% |
| 8B-Q4_K_M | 5027783488 | 78.0% |
| 14B-Q4_K_M | 9001753376 | **139.7%** |

The 14B cell does not fit in one device's working set at all; at 139.7% of the budget it must
spill to host memory, which is a different residency regime with a different cost structure. The
excluded upper interval, 5.028 → 9.002 GB, is exactly the interval that crosses that boundary: it
runs from 78.0% of the budget to 139.7%, and it is the only interval in the series that crosses
100%. The exclusion is therefore mechanistic, and the 17.0σ delta is a consequence of the regime
change rather than the reason for excluding the interval.

**Lower bound, by fixed-cost dominance, and not by residency.** The 0.6B cell sits at 9.9% of the
budget and is comfortably resident, so residency cannot exclude that end — the same argument that
works above does not work below, and it is not used. What excludes the interval below 2.497 GB is
the slope itself: `18.02 ± 0.16 ms/GB` there against `5.84 ± 0.46 ms/GB` immediately above it,
25.1σ apart. The fixed overhead that a per-byte slope cannot absorb is concentrated in that
interval, which is the same curvature the gate's residual signs `- + + - -` reported from the
other direction.

## The cells, N, and the per-cell variation

Five cells. N = 20 measured invocations per cell, from three warmups discarded per cell before
the measured block. Coefficient of variation across those invocations, on `tg128`:

| cell | CV |
|---|---|
| 0.6B-Q8_0 | 1.10% |
| 4B-Q4_K_M | 0.43% |
| 4B-Q6_K | 0.53% |
| 8B-Q4_K_M | 0.29% |
| 14B-Q4_K_M | 0.65% |

The between-invocation spread is the sigma the secants are computed with. It is widest relative to
the within-invocation spread at 14B-Q4_K_M, 4.8x on `tg128` and 4.3x on `pp512`, which is why the
invocations are separate processes rather than repetitions inside one; the log prints both
spreads side by side.

## What this is not

This is a **bounded marginal cost over a stated region** — 2.497 to 5.028 GB of model on two
D700s in tensor split, decoding 128 tokens — and it is not a bandwidth and not a model of the
full range. No bytes-per-second figure is implied here or derivable from it: inverting ms/GB
would not produce a bandwidth, because the quantity is not linear across the range and the two
end intervals are excluded for two different reasons. It also asserts nothing about 0.639 →
2.497 GB or 5.028 → 9.002 GB, and it specifically does not assert that cost per byte is constant
inside the window — the 2.69σ disagreement between the two shipped secants is the direct
measurement that it is not.

## Reproducing it

With the committed CSV and the committed tool, the command above reproduces the pasted stdout
byte for byte and exits 1. The window's residency comparison reproduces from the device budget
printed by the probe and the five byte counts on the command line, all five of which are the GGUF
sizes of the cells that ran. The cell count, N, warmup policy and coefficients of variation are
in `tools/calibrate/results/calibration-5cell-2026-10-18.log`; the invocation itself is in
`tools/calibrate/cells.json`.
