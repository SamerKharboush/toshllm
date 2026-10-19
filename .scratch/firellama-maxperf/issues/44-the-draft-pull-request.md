# 44: the draft pull request opens now

Status: ready-for-agent
Type: task
Blocked by: 43
Spec: ../spec.md (Revision 4)

## Problem

The work has been local for the whole of this effort. A fork with issues disabled does
not block a pull request; a remote resolving to upstream read-only does, and that is a
default-repository setting rather than a permission. Waiting for a green gate is not
required and would be dishonest, since the gate currently rejects and the rejection is
the finding.

## Change

Open a draft pull request against the fork with the default repository set to the fork
first so the push and the create both target a writable remote.

The body carries, in this order: the gate's committed REJECT evidence, the two dead
routes with their arithmetic, the bounded claim from ticket 43, the ticket statuses,
and the sigma-mislabelling defect that was found and fixed in this round. The negative
results go in the body rather than in a ticket comment, because they are what make the
surviving claim credible -- sixteen subsets tested, three functional forms rejected,
one quadratic still failing -- and a reader who cannot see them cannot tell the window
from a cherry-pick.

## Evidence

The pull request URL, and its head resolving to the pushed commit. The patch-series job
green, the contract job green, and the performance gate red for the stated reason:
`REJECT`, worst |z| 32.5, reduced chi-squared 774.1, exit 1. Red is the expected state
and the body says so.
