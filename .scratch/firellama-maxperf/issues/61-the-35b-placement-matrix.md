# 61: the placement matrix on the 35B, with both cards enrolled

Status: ready-for-agent
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
