# The AVX2 audit as specified cannot fail

Found while checking whether ticket 52 could run here. This is a check that would have
passed everything and proved nothing.

## The measurement

Three binaries in a local llama.cpp tree, audited as ticket 53 specifies:

```
build/tools/llama-bench   192 B   avx2_hits=0
build/bin/llama-bench   16664 B   avx2_hits=0
build/bin/llama-server  20760 B   avx2_hits=0
```

`build/tools/llama-bench` is **192 bytes** -- a wrapper, not a Mach-O engine. `otool -tvV`
on it emits nothing, and `grep -c` therefore returns 0. **A shell script passes the audit.**

## Why this matters

Ticket 53 and the brief for it both propose: disassemble the binary, grep for AVX2-only
mnemonics, and treat an empty result as proof that the label is true. The negative control
above shows that empty result is also what a non-binary, a wrapper, and a stripped or
malformed file produce. The check as written answers "did grep find anything", not "is this
binary free of AVX2".

This is the same defect the repo already has a rule about: a control that changes nothing
proves nothing. It is also the second instance in this effort of a check that could not fail
-- the first being the sigma array printed without cell names, which reached a published
number.

## What makes it falsifiable

The audit needs **both** controls, not just the absence:

1. **Positive control.** A binary known to contain AVX2 must produce hits. Without one, a
   zero is indistinguishable from a broken pipe, a wrong file, or a wrapper.
2. **Identity proof.** The file being audited must be confirmed to be a real Mach-O
   executable of plausible size, with its ARCH and LC_BUILD_VERSION load commands recorded,
   before its disassembly means anything.

The 20 KB files in that tree are not the engine. Whatever llama.cpp build produced them
wraps or stubs the real binary elsewhere, and the real one must be located before any audit
of it is meaningful.

## Consequence for the tickets

- **53** gains a required positive control and an identity check. An empty grep alone is not
  its evidence.
- **52**'s premise is revised: a generic llama.cpp *clone* exists locally at commit 3d82ef6,
  so the AVX1 comparison may be runnable on one machine after all -- same silicon, two
  builds, which is a stronger comparison than the cross-machine one originally specified.
  Whether it is runnable depends on finding the real binaries, which is unresolved.
