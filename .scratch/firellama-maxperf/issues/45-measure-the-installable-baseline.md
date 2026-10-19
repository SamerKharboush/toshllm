# 45: capture the installable baseline

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 6)

## Problem

The baseline for every claim is the engine inside the shipped app, and it has never been
extracted or run. No user installs stock llama.cpp, which is what all prior comparisons used.

## Change

Install the 0.87.26 noavx2 build, launch it once, and capture the engine process's exact
argument vector and environment from the live process. Extract the bundled binary, hash it, and
record its code-signing identity and build-version load command. Then run the extracted binary
with that captured configuration and prove the extraction is faithful with a 0.6B smoke test
and a `--version` run.

## Evidence

The captured argv and env committed verbatim, the sha256, the codesign identity, and the smoke
test output. Then one run through the app comparing its own reported throughput against the
extracted binary's band: if they disagree, the extraction is wrong and this ticket reopens.
