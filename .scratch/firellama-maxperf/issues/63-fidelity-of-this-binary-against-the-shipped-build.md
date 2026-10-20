# 63: fidelity of this binary against the shipped build

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

This fork replaces the engine that ships in the app. A faster engine that answers differently
is not a faster engine, and the release has no row saying the two agree. The spec requires
this row before any release, and it has to be a row about the same binary that was measured,
not about a build someone else made.

## Change

Temperature 0, a fixed set of prompts, both binaries, the same model and the same context.
Compare the generated text, not the timings. The shipped build is the engine inside
`ToshLLM.app` (sha256 recorded), not a re-build of it.

## Done when

- One row per prompt, both binaries, the outputs either identical or the difference named.
- The model, the context, the prompt list and both sha256 values in the method line.
- No release ships without this row.
