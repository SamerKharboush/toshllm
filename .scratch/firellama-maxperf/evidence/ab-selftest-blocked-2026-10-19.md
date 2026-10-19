# The preflight stopped the run, and the cause is not yet known

First execution of `tools/ab.sh`. It never produced a row, because `preflight()` refused.
That is the gate working, and it is the first time in this effort a gate stopped a bad
measurement before it happened rather than after.

## What ran

```
preflight[baseline]: --version -> version: 0.6.0-dev (build 11429, commit d81235049)
preflight[baseline]: -ngl 0 served, produced 32 tokens
preflight[baseline]: -ngl 99 FAILED to serve, exit=134
    12  llama-server  0x...09 _Z12llama_serverR13common_paramsiPPcR12server_child + 26617
    13  llama-server  0x...5d _Z12llama_serveriPPc + 237
    14  dyld           0x...30 start + 3056
ab.sh: preflight failed: the baseline is not fit to measure
```

Exit 134 is SIGABRT. The CPU path works; the offloaded path aborts inside the server.

## Two readings, and the data cannot separate them yet

**Reading A -- a real capability difference.** The shipped 0.87.26 build cannot offload
to GCN 1.0 and aborts when asked. If true, this is the finding the whole effort was
looking for, and it means the A/B at `-ngl 99` is impossible for the baseline rather
than merely slower.

**Reading B -- a missing configuration.** The harness used a fixed invocation. The app
supplies its own argument vector and environment, and the premise of ticket 45 is that
those are load-bearing -- 0.87.26 specifically repaired a VRAM-reserve value that was not
reaching the engine. If the app sets something that makes Metal work, this abort is
artefact of my invocation, not a property of the binary.

**Reading B is the more likely one and must be excluded first**, because it is cheap to
exclude and because assuming Reading A would repeat this effort's recurring error of
concluding from a configuration nobody ships.

The next step is therefore not more benchmarking. It is capturing what the app actually
executes when it drives its bundled engine -- the ToshLLM launch agent or the app's own
spawn path, not `com.user.llama-server`, which is a different job.

## A defect in how I reported this

The command was piped through `tail -30`, so `$?` was `tail`'s status, not the harness's.
The "harness exit: 0" in the transcript is therefore meaningless and I am not treating it
as a result. The harness's own message -- `preflight failed: the baseline is not fit to
measure` -- is the finding.

This is the second time in this effort I have reported an exit code read through a
pipeline. The first was `grep -c` after `strings`, which reported failure on a match by
way of SIGPIPE. The pattern is the same and it is mine, not the tooling's.

## What this establishes regardless of which reading holds

`preflight()` does what it was built to do. A binary that serves on the CPU path and dies
on the offloaded path is precisely the case a `--version` check alone would have passed,
and precisely the case that would have poisoned a twenty-block run with silent failures in
half the blocks.
