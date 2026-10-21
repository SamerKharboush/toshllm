# 68: the shipped build answers the 27B Q8_0 with zeros

Status: open
Type: bug
Spec: ../spec.md (Revision 8)

## Problem

The build in `/Applications/ToshLLM.app` (the 0.87.26 release) runs the same llama.cpp
commit as this fork's engine, `d81235049`, with the fork's earlier patch set and a
different compiler (AppleClang 21 against our 17). On a dense 27B Q8_0 it answers every
token with zero.

| build | placement | the answer |
|---|---|---|
| the shipped 0.87.26 build | the host (`-ngl 0`) | `"0000000000000000"` |
| this build | the host (`-ngl 0`) | `"A binary search tree (BST) is a data structure where each node has"` |
| the shipped 0.87.26 build | one card (`-ngl 99 -sm tensor`) | aborts in `ggml_backend_meta_get_split_state` |
| this build | one card (`-ngl 99 -sm tensor`) | runs the cell, and the answer degenerates after 25 characters (R20) |

The shipped build's host decode on this model is 1.1659 tok/s (sd 0.0038, n=2) against
this build's 1.5972 tok/s, so it is 27% slower and wrong.

The same difference is visible on a model that fits: the 0.6B Q8_0 on the host answers
" 1. 2 2. 3 3. 4 4. 5 5." on this build and " The answer is 2. But why is that the case? ..."
on the shipped build. Both are coherent, and they are not the same answer: the two CPU
paths round differently. R18 already recorded the same thing on the 35B (1 of 2 prompts
identical, diverging at character 85, where the logits are a near-tie).

## Why it matters

A build that answers with zeros and a build that answers with a different coherent answer
are the same class of problem, and the second is the dangerous one: the user cannot tell
that the model is not being computed. The zero answer at least looks wrong.

This is a defect in the shipped build, not in this fork, and the fork's answer is the
reference. What is not yet known is which change fixes it: the fork's 50-patch series, the
compiler (AppleClang 21 against 17), or the patch set the 0.87.26 release carries against
the one this build carries.

## Change

Not for this fork: the fork already answers the model. The question is which of the three
differences between the two builds fixes the shipped one, so the next release does not
regress. The suspects are the 0.87.26 patch set and the compiler, and the first thing to
try is the shipped patch set with this build's compiler.

## Done when

- The zero answer is attributed to a specific difference between the two builds, with a
  run that shows it.
- The fork's build is shown not to have the defect, on the same model and the same prompt
  (it is: the row above).
- If the difference cannot be attributed with the time available, the record says so and
  leaves the three suspects named.

The evidence is in `../evidence/the-27b-q8-0-on-this-machine-2026-10-20.md`.
