# 41: the probe reports the working-set budget

Status: resolved
Type: task
Spec: ../spec.md (Revision 4)

## Problem

The proposed window, 2.50 to 5.03 GB, is currently the pair of secants that happened to
sit close together. That is what a cherry-picked window looks like whether or not it is
one, and no amount of careful wording fixes it: the window has to be defended by
mechanism. The mechanism available is residency, and the quantity it needs -- the
device's recommended working-set budget -- is one nothing currently reports.

## Change

The probe gains a per-device reading of the recommended working-set budget, in bytes,
printed alongside the device name and index it already reports. The probe is already
this project's instrument for per-device facts, so this is a new reading on an existing
seam rather than a new tool.

## Evidence

The budget per device on this machine, in bytes, next to the device index. Then the
comparison the window rests on: each calibration cell's model bytes against the budget,
for at least the cells bounding the two interior intervals. State the comparison as it
comes out. This ticket does not decide whether the window holds -- it produces the
reading that ticket 42 decides on.

## Answer

`tools/metal-probe/threadgroupprobe.m`, merged. Each device now reports
`recommendedMaxWorkingSetSize` in bytes, with two companion lines naming the source
property and stating that it is a driver recommendation rather than a hard limit, so a
reader does not have to guess which.

On this machine both D700s report 6442450944 bytes, 6.00 GiB each.

The reading decides ticket 42, and it decides it asymmetrically: the upper end of the
published window is excluded because the 14B cell needs 139.7% of that budget and must
spill, while the lower end sits at 9.9% and is excluded by fixed-cost dominance rather
than by residency. Ticket 42 carries the comparison and the consequence.

The measurement in `evidence/threadgroup-memory-2026-10-18.md` was produced by the
earlier probe build and its recorded sha remains the sha of that build. Extending the
probe does not revise a past measurement, and the evidence file is a record of one.
