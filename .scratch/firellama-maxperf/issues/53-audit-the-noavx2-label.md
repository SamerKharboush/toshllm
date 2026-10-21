# 53: audit the noavx2 label

Status: resolved
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

## Answer

Ceiling stated honestly rather than maximised:

> No AVX2 instruction was found in **107,586,373 bytes** of `__TEXT` disassembly of the
> shipped engine, using a scan shown to detect them, and the binary executes cleanly on
> this Xeon under both offload settings.

Three legs, all recorded: the build recipe targets no-AVX2; the whole disassembly is clean
under a widened pattern with control 3 hits and subject 0; and the binary runs, reporting
`0.6.0-dev (build 11429, commit d81235049)` -- which is the same llama.cpp pin this repo's
39-patch series targets.

**The ticket's own pattern was too narrow**, and that is the finding worth keeping. It
scores a genuine AVX2 binary at zero because `otool` renders the instruction as `vpermps`.
A hand-written mnemonic list is incomplete by construction; the widened pattern is the
instrument and every hit is a flag rather than a verdict.

The control is committed as source and rebuilt per run, so it cannot rot into a passing
fixture. Its `used`/`noinline` attributes are load-bearing: without them the optimiser
deletes the function and the control silently scores zero.

Evidence: `evidence/noavx2-audit-2026-10-19.md`.
