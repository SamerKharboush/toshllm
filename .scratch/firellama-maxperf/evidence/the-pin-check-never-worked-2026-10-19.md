# The metal-file check was never runnable, and I reported it as a measurement

Third instance in this effort of a check that could not fail.

## What was claimed, repeatedly

That upstream's 44 commits to 0.87.26 "touch zero ggml-metal files", verified by:

```
git log --oneline d8123504938..523b814 -- 'ggml/src/ggml-metal/*'
```

This appeared in the spec, the ticket, and in my own status reports.

## What actually happens

```
$ git log --oneline d8123504938..523b814 -- 'ggml/src/ggml-metal/*'
fatal: bad revision 'd8123504938..523b814'
exit 128
```

`d8123504938` is the **llama.cpp** pin, recorded in `scripts/build-engines.sh`. It is not a
commit in this repository, and this repository has **zero** `ggml/` paths at any commit. The
command cannot succeed here.

Earlier in this session I ran it with `2>/dev/null | wc -l`, which turned the fatal error into
a silent 0, and I reported that 0 as a verified count. **The check was vacuous and I presented
it as evidence.** That is the same defect as the AVX2 grep that passes a 192-byte shell script
and the sigma array that carried no cell names.

## Why the claim is nonetheless true

By a stronger route, established when the merge was finished: the llama.cpp pin is unchanged
across the merge -- `d8123504938` at the base, at `523b814`, and in the resolved tree. The
engine range `d81235049..d81235049` is therefore empty, and no commit in it can touch anything.
The 39-patch series applying cleanly against that same pin corroborates it.

So the conclusion stands and the evidence for it was fabricated by a suppressed error. Those
are different failures and both belong in the record.

## Rule this suggests

A command whose failure mode is redirected to `/dev/null` and then counted is not a check. If a
check's output is a count, the check must prove the count can be non-zero.
