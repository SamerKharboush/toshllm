# 50: release or withdraw

Status: ready-for-agent
Type: task
Blocked by: 49
Spec: ../spec.md (Revision 5)

## Problem

A stale download page is worse than no download page. The fork's last release is
v0.87.14-beta.1 while the branch carries 48 commits of work, so the published artifact and the
code have diverged.

## Change

Either cut a release on the synced base carrying these upgrades, or mark the older release as
superseded. On this hardware the variant is not a preference -- the Xeon has AVX but no AVX2,
and this repo has already shipped one "noavx2" download that was silently compiled with AVX2
and SIGILLed with exit 132 on exactly these machines. Verify the variant by disassembly for
the absence of AVX2/FMA/BMI2 opcodes AND by running the artifact and generating text.

## Evidence

The release URL or the superseded notice, the disassembly evidence, and a run of the artifact
on this machine.
