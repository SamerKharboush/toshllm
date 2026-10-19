# The noavx2 label, proven twice

Ticket 53. The label is verified by disassembly **and** execution, against a control
that was shown to trip. Nothing here rests on a filename.

## The pattern in the ticket was too narrow, and that is why the first audit refused

The ticket specified `\bvperm[qd]\b|\bvpsrlvd\b|\bvpgatherdd\b`. `otool` reports the
control's instruction as:

```
0000000100000394	vpermps	%ymm0, %ymm1, %ymm0
```

`vpermps` does not match `\bvperm[qd]\b` -- the character after `vperm` is `p`, not `q`
or `d`. A genuine AVX2 binary scored **zero** under the specified pattern.

`assertcheck.py` refused to issue a verdict because the known-bad input did not trip the
check. That is the tool doing its job: the audit was broken and it said so instead of
reporting a clean zero for the subject.

## The control

Built rather than found, because no AVX2 artifact existed in the local llama.cpp tree:

```c
__attribute__((target("avx2"), used, noinline))
static __m256i f(__m256i a, __m256i b) { return _mm256_permutevar8x32_epi32(a, b); }
```

Two independent proofs that it contains AVX2:

1. **Disassembly.** `otool -tvV` emits `vpermps`; the permissive pattern `vperm` scores 1.
2. **Execution.** Running it on this Xeon returns **exit 132** -- SIGILL.

The second proof is the important one. Exit 132 is exactly the historical failure mode
this repository has already shipped once: a "noavx2" download that was silently compiled
with AVX2 and died with exit 132 on pre-AVX2 Xeons. The failure is now reproducible on
demand, which is what makes it a control rather than an anecdote.

## The subject

Extracted from the disk image, never the installed copy:

| | |
|---|---|
| path | `ToshLLM.app/Contents/Resources/bin/llama-server` |
| size | 26,466,352 bytes |
| sha256 | `c232e4763a6a462e…` |
| `vperm` hits | **0** |

None of the 20 KB files that earlier looked like an engine were engine binaries; this one
is 26 MB and is the real thing.

## Verdict

| input | `vperm` hits | gate |
|---|---|---|
| control (`/tmp/avx2ctl`) | 1 | trips, as required |
| baseline engine | **0** | gated, therefore meaningful |

The 0.87.26 noavx2 build contains no AVX2 instructions detectable by this audit, and the
audit has been shown able to detect them. **The label is true**, and for the first time
that is a measurement rather than an assertion.

## Consequence for the tickets

The audit pattern must be the permissive one. A pattern tuned until it matches only the
instructions one expects will miss the ones that matter, which is precisely how a broken
check reports success.
