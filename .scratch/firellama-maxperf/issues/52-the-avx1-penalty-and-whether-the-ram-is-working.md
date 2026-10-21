# 52: the AVX1 penalty, and whether the 64 GB is working

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 5)

## Problem

Two unmeasured things, both cheap. The Xeon has AVX but not AVX2, and every measurement so far
measured GPU paths, so the CPU's contribution has no number. And "unused RAM" has been assumed
rather than measured: llama.cpp already puts non-offloaded layers and KV cache in RAM, so the
memory may be working and the premise may be wrong.

## Change

Measure the AVX1 penalty: same model, -ngl 0, this build's CPU path against a generic build's
CPU path on comparable silicon, reported per token. Then check whether the 64 GB is actually
idle or working during -ngl 99 decode, sampled during the run rather than after it.

## Evidence

The per-token delta with its method line, and an answer to whether the RAM is idle. If it is
idle, name what a cache tier would buy and at what complexity -- or say it would buy nothing.

## Revision 7 note

Re-scoped by Revision 7: the evidence is the launchd plist, never a process environment. The job is deregistered rather than killed, and the respawn behaviour is recorded as a hazard note, because a restarting twelve-thread server would be indistinguishable from variance across an alternating A/B.
