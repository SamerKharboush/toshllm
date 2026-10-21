# 50: release or withdraw

Status: ready-for-agent
Type: task
Blocked by: 47, 49
Spec: ../spec.md (Revision 6)

## Problem

A stale download page is worse than no download page, and a package built before the verdict
exists ships a number nobody measured.

## Change

Gate on the verdict. Then either cut 0.87.26-beta.1-noavx2.dmg on the synced base carrying these
upgrades, or mark the older release superseded. On this hardware the variant is not a
preference: the Xeon has AVX but no AVX2, and this repo has already shipped one "noavx2"
download that was silently compiled with AVX2 and SIGILLed with exit 132 on exactly these
machines. Verify by disassembly for the absence of AVX2-only mnemonics AND by running it.

## Evidence

The release URL or superseded notice, the disassembly evidence, a SIGILL-free run on this
machine, and a release note whose wording matches the verdict -- parity included.
