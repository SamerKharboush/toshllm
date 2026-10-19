# 53: audit the noavx2 label

Status: ready-for-agent
Type: task
Blocked by: 45
Spec: ../spec.md (Revision 6)

## Problem

The baseline's variant is the one property that, if false, invalidates every number measured
from it. This repo has already shipped a "noavx2" download compiled with AVX2 that SIGILLed
with exit 132 on exactly these Xeons, so the filename is not evidence.

## Change

Disassemble the extracted baseline binary and grep for AVX2-only mnemonics. Then run it on this
machine. Both must pass. If the previous mislabelled artifact is still on disk, use it as the
negative control that proves the grep can actually fail.

## Evidence

The disassembly grep output committed verbatim -- an empty result is the proof -- and a
SIGILL-free run from the same binary. If either fails, stop the round: the baseline is invalid
and no number from it may be published.

## Revision 7 note

Gated by Revision 7: the check must first run against a binary known to contain AVX2 and see a non-zero hit, before it may report zero for ours. The build tree on this machine is real, so a genuine artifact exists to serve as that positive control; locating it is part of the ticket. A wrapper, a shell script, or a truncated read must be rejected as not-a-binary.
