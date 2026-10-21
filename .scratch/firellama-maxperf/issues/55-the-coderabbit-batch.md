# 55: the CodeRabbit batch

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 7)

## Problem

A review raised seven findings. Five are trivially correct, one has a deeper fix than the
review proposed, and one repeats a conclusion this effort reached from first principles. They
are batched because they are small and because one of them touches the patch series, which
means it carries its own proof.

## Change

Six accepted, one verified before any patch is written.

The api-key redaction is accepted, but the shallow fix is not enough: a secret must never
appear with a value in any committed file, including a replay recipe. The recipe substitutes
from the keychain at replay time, so the document stays replayable and the secret stays out of
the repository.

The finding that the existing calibration harness cannot produce the A/B is accepted and folded
into ticket 46 rather than opening a ticket for it. It independently confirms the harness-first
decision: that harness measures a single binary sequentially, counts discarded warmups as
invocations rather than tokens, and shells out to a benchmark tool rather than the engine under
measurement.

Accepted as written: the Ukrainian translation typo, the sympy media decline gated on the
client-tools flag, the temporary directory in the rebrand script given a trap, and the stale
Spanish VRAM sentence that contradicts the current default.

**Verified before patching, not patched blind:** the finding that the MCP agent patch may
already hold its invariant. The claim is conditional -- it says the flag may be reachable
through another configuration -- and the condition is not proved. Check the app's engine-extension
and sympy tool sources for a second path that sets the flag with the bundled agent. If none
exists, skip with that reason stated in the pull request thread. If one does, patch it.

## Evidence

One commit carrying the six accepted fixes. If the MCP patch is edited, the patch-series check
must exit zero **in that same commit** -- a patch under the series is not a file, it is a claim
about provenance, and the proof belongs with the change rather than after it.

Replies on the pull request thread for every finding, including the skipped one with its reason.
