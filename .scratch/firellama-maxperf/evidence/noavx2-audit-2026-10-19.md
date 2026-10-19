# The noavx2 label: no AVX2 found in 107 MB of disassembly, and the binary runs

Ticket 53, at its honest ceiling. The claim is **not** "the label is true". It is:

> No AVX2 instruction was found in 107,586,373 bytes of `__TEXT` disassembly of the
> shipped engine, using a scan shown to detect them, and the binary executes cleanly on
> this Xeon under both offload settings.

Those are three legs and the release note should carry all three.

## Leg 1 -- the build recipe sets a no-AVX2 target

Carried by the project's engine build configuration, not re-derived here.

## Leg 2 -- the disassembly is clean, under a widened pattern

The ticket's original pattern was `\bvperm[qd]\b|\bvpsrlvd\b|\bvpgatherdd\b`. It scores a
genuine AVX2 binary at **zero**, because `otool` renders the control's instruction as
`vpermps` and the character after `vperm` is `p`, not `q` or `d`.

A hand-written mnemonic list is incomplete by construction and will miss the next one too.
The widened pattern, where every hit is a flag rather than a verdict:

```
\bvperm|\bvpbroadcast|\bvpgather|\bvpsrlv|\bvpsllv|\bvpmaskmov|\bvpermi2|\bvpermt2
```

| input | widened hits | disassembly bytes |
|---|---|---|
| control (`tools/controls/avx2_control.c`) | **3** | 861 |
| baseline engine | **0** | **107,586,373** |

Coverage is stated because it changes the claim. A scan of part of a 26 MB binary is not
the same assertion as a scan of all of it, and nothing in the earlier output distinguished
them.

## Leg 3 -- it executes, on both paths

The extracted engine runs and reports itself:

```
version: 0.6.0-dev (build 11429, commit d81235049)
```

**That commit is the llama.cpp pin this repository's patch series is written against.** The
shipped 0.87.26 engine and our 39-patch series target the same upstream revision, which is
a provenance fact worth recording independently of the audit.

## The control

Committed as source, rebuilt on every run, never as a binary. If it stops tripping, the
harness fails rather than passing:

| property | expected | observed |
|---|---|---|
| widened scan | >= 1 hit | 3 |
| execution | 132 (SIGILL) | `Illegal instruction: 4` |

`used` and `noinline` are load-bearing in that source file. Without them the optimiser
deletes the function, the control scores zero, and a check rots into a passing fixture --
which is exactly the failure this file exists to make impossible.

## What this does not establish

The audit reads the x86_64 slice. It says nothing about whether a kernel the scan did not
reach would fault, which is why leg 3 runs both `-ngl 0` and `-ngl 99` and why `ab.sh`'s
preflight refuses to emit a row until both are SIGILL-free. A clean disassembly and a clean
smoke test are two different claims and the release note keeps them separate.
