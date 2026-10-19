# The default build dies with SIGILL, and the AVX1 delta is a flag not a branch

## The rebuilt engine executed AVX2 this Xeon does not have

Built straight from the branch with `./scripts/llama-build.sh`:

```
version: 0.6.0-dev (build 11429, commit d81235049)
sha256:  e01c4be7e392e1ee171bd042117aec13c7fa0ae0566d9227f19bb37f927785b1
size:    27,056,432 B
```

First invocation, `-ngl 99 -sm tensor`, 0.6B:

```
Illegal instruction: 4        exit 132 = SIGILL
```

Not SIGABRT. The tensor-split question has still not been reached, because the binary dies
before it gets there. AVX2 mnemonics in its `__TEXT`:

| mnemonic | count |
|---|---|
| `vpbroadcastd` | 1798 |
| `vpermps` | 88 |
| `vfmadd132ps` | 10 |
| `vpermd` | 7 |

The AVX2 control from ticket 53 returns 3 hits for the same class of mnemonic, so this is 600x
the control's density, and execution confirms it.

## The build script already knows, but its default is wrong

`scripts/build-engines.sh`:

```
140  TOSH_AVX1=1   -> -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=ON -DGGML_BMI2=OFF
143  default      -> -DGGML_AVX=ON -DGGML_AVX2=ON  -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON
146  TOSH_NO_AVX2=1 -> everything off  (SSE4.2 baseline)
```

The middle variant is the only one that runs on a D700-era Mac Pro, and it is not the default.
So `./scripts/llama-build.sh` on the target hardware produces a binary that dies on first
instruction. That is a release defect, not a measurement problem, and it is why upstream ships
a separate `-noavx2` DMG.

## The AVX1 delta is a build flag, not a branch difference

This is the correction to the round's strongest-looking claim. Our stale bundle reported
`AVX = 1 | F16C = 1`; the shipped build reported neither. But that comparison is between two
`cmake` invocations of the same source, not between two bodies of work:

- Upstream ships **SSE4.2-only** because they cannot know their user's CPU.
- We ship **AVX1+F16C** because we know it is a Xeon E5 v2.
- Any user could rebuild upstream with `-DGGML_AVX=ON -DGGML_F16C=ON` and get the identical
  delta, with none of this fork's patches.

So "our CPU path is faster than theirs" is a **packaging** claim, and it is only defensible if
we say so in those words: this fork ships a build tuned for the machine it targets. It is not a
code differentiator, and the release note must not present it as one. The measurement the user
asked for is still worth taking -- it quantifies what the packaging choice buys -- but it
measures a flag.

## Where the differentiator list stands after this

| hypothesis | status | instrument |
|---|---|---|
| wave64 decode | **struck** -- both binaries emit it | log diff |
| tensor split | **unresolved** -- binary died before the test | `-sm tensor` on a working build |
| AVX1+F16C CPU path | **packaging, not code** | `pp512 -ngl 0`, both builds |

One hypothesis remains that could be a genuine code differentiator. It has not yet been tested,
because two builds in a row failed for reasons unrelated to it.
