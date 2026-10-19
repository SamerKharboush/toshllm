# 41: the probe reports the working-set budget

Status: ready-for-agent
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
