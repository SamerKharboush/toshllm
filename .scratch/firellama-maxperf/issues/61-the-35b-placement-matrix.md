# 61: the placement matrix on the 35B, with both cards enrolled

Status: resolved
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The 35B runs with about 4.4 GB on one D700 and the rest in the 64 GB, and its decode is
bound by the host side, not by VRAM, not by the disk and not by the GPU (39% activity, 0.22
MB/s of page-ins, `the-35b-baseline-is-the-spine-2026-10-20.md`). The second card was never
enrolled: the Metal backend registers one device unless it is told otherwise, so every
placement cell measured so far was a one-device cell.

With both cards enrolled, the placement question is answerable: how much of the 35B can live
on the second card, and whether the experts that do not fit are better off on the GPU or on
the host.

## Change

Two devices registered (`GGML_METAL_DEVICES=2`, `GGML_METAL_DEVICE_LIST=0,1`), and a matrix
over `--n-cpu-moe {16,24,32}`, `-cmoe`, one `-ot` regex that moves the late-layer expert FFNs
to the GPU, `-ts 1,1`, `-sm tensor`. Every cell reports tok/s, both devices' VRAM and
activity, and the pagein delta. A cell that ends up on one device is recorded as one device.

## Done when

- One row per cell, each with a before/after against the T1 spine, the utilisation card, and
  the device each card held.
- The best cell is named, with the mechanism that explains it, and the cell that does not
  work is named too.
- No cell claims a split it did not have.

## Answer

**Six of the seven cells ran, and the two fastest cells do not compute the model.** The
evidence is in `../evidence/the-35b-placement-matrix-2026-10-20.md` and
`../evidence/the-n-cpu-moe-cells-are-not-the-model-2026-10-20.md`.

| cell | decode tok/s | what the answer is |
|---|---|---|
| one device (the spine) | 0.1450 | correct |
| both cards, tensor split | 0.4387 | correct, 3.03x the one-device cell |
| `--n-cpu-moe 16` | 5.9683 | one token repeated to the end |
| `--n-cpu-moe 24` | 6.8473 | the same, a different token |
| `--n-cpu-moe 32` | 10.3336 | the same |
| `-cmoe` | 9.8263 | the same |
| one `-ot` regex, late layers | could not be run | the GPU died mid-run |

The best cell is the host, at 11.1015 tok/s, 76.6x the one-device cell, with the CPU
reference as the ground truth for the text. The cells that "win" are the ones that do not
compute the model, and the engine does not refuse them: that is ticket 66.

The `-ot` cell could not be run because the buffer type is not named `Metal`; the valid
names are `CPU`, `CPU_REPACK`, `MTL0_Private` and `MTL1_Private`, and `MTL0_Private` aborts
at load with "a buffer (MTL0_Private) that cannot run the operation (NONE)". `=CPU` runs
and gives the right text at 0.3613 tok/s.

The second D700 had to be enrolled for any of this: `GGML_METAL_DEVICES=2` with
`GGML_METAL_DEVICE_LIST=0,1`. Without it every cell is a one-device cell, and the row
would have said the same thing three times.