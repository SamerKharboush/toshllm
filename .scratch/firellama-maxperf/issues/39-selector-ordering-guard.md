# 39: wave64 requests the _lds32 form first

Status: ready-for-agent
Blocked by: 16
Spec: ../spec.md (Revision 2)

## Problem

The selector requests the plain FA AMD kernel on wave64 and only falls back to the
_lds32 twin after the build fails. On GCN the plain form is refused, so the fallback
is the normal path and the failure is paid once per process for nothing.

## Change

An ordering change: on wave64, request the _lds32 form first rather than the plain
form. NOT a prohibition. Ticket 35 leaves two readings standing that the data cannot
separate -- the twin may exist because the plain form overflows, or the plain names
may be leftovers that were never viable -- and a prohibition would assert the second,
which would be wrong on any hardware where the plain form does build.

## Evidence

Blocked. The guards correctness is unproven until the engine run confirms which
reading holds, and that run needs pipeline-level logging. Do not implement this on
the strength of the probe table alone.
