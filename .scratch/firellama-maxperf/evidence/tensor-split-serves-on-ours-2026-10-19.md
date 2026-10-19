# Tensor split serves on this branch and aborts on the shipped build

## The result

Same machine, same model (0.6B-Q8_0), same flags except split mode:

| binary | `-ngl 0` | `-ngl 99` | `-ngl 99 -sm layer` | `-ngl 99 -sm tensor` |
|---|---|---|---|---|
| shipped 0.87.26 `-noavx2` | SERVED | SERVED | SERVED | **SIGABRT, exit 134** |
| this branch, AVX1 build | SERVED | -- | -- | **SERVED** |

Engine identity for the serving build:

```
version: 0.6.0-dev (build 11429, commit d81235049)
sha256:  fce9e70e875bcb69cb0b3cf358f41ddcefa41c00c4a4a5cf157386c5d593ef70
AVX2 mnemonics: vpermps = 0
VERSION file at HEAD: 0.87.26-beta.1
```

The baseline's abort site, from its own stderr: `ggml_abort` inside
`ggml_backend_meta_get_split_state`, reached from `ggml_backend_meta_buffer_init_tensor_impl`,
after warning `automatic fitting is not implemented for --split-mode tensor`.

This branch serves. `patches/llama/core/0038-engine-tensor-split-falls-back-to-layers.patch`
converted 39 abort paths into a named exit 86; on this input it never needs to fire, because the
split state resolves.

**This is the capability difference the fork was built for, on the axis the fork was built for,
and it is the first claim in this effort that has survived its own test.**

## The confound, stated rather than buried

The two binaries differ in ISA variant: the baseline is SSE4.2-only, ours is AVX1+F16C. The
abort is in scalar C++ split-state logic where ISA should be irrelevant, but "should be" is not
a control.

The control that settles it: build the baseline's variant from **our** source at `TOSH_NO_AVX2=1`
and run `-sm tensor`. If it serves, the ISA is exonerated and the patch is the cause. If it
aborts, the finding is confounded and must not be published as a code differentiator. That is
one build and one run, and it is the next thing to do.

## Still owed before this is a claim

1. The ISA control above.
2. Repeat at 8B, per D1 -- 0.6B split across two 6 GB cards is an unusual allocation shape and
   an abort there could have been size-dependent. Ours serving at 0.6B does not prove it serves
   at 8B.
3. Determinism: 10/10 identical outcomes, not one run each.
4. The baseline re-tested in the same session, so thermal state and background load match.

One run each is a lead. It is a very good lead -- it is the first one that has not dissolved on
contact -- but it is one run each.
