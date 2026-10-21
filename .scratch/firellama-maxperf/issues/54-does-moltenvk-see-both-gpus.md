# 54: does MoltenVK see both GPUs

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 6)

## Problem

The Colibri question contains an assumption nobody has tested: that a Vulkan path on this
machine could use both D700s. Whether MoltenVK enumerates one device or two settles it in
minutes and decides whether any further work is warranted.

## Change

Run the Vulkan device enumeration under MoltenVK and record what it reports. If it reports one
device, "Colibri can use our dual GPU" is answered NO and no porting work begins. If it reports
two, do one short run and then decide.

## Evidence

The enumeration output committed verbatim, and the consequence stated: either the dual-GPU
claim for Colibri is closed, or one run follows.
