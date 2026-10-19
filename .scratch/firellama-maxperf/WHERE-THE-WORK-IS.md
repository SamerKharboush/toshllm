# firellama-maxperf: where the work is

Spec: `spec.md` (Revision 4 is current; its "Decisions taken" subsection is binding).
Tickets: `issues/NN-*.md`, frontier computed from `Blocked by:` and `Status:`.

## Pull request

https://github.com/SamerKharboush/toshllm/pull/2 — draft, base `main`, head
`phase1-metal-d700-optimization`.

Created with the fork set as the default repository
(`gh repo set-default SamerKharboush/toshllm`), because `gh` otherwise resolves to
upstream and reports read-only. The fork has issues disabled; that never blocked a pull
request and was not the obstacle.

The performance gate is **expected red**. `REJECT` with a named cause is this work's
finished state, not a failure of it. The pull request body says so.

## Open tickets and their order

- **40** the secant tool is the claim — ready
- **41** the probe reports the working-set budget — ready
- **42** the window is justified by residency or withdrawn — after 41
- **43** the claim ships as a file — after 40 and 42
- **44** the draft pull request — after 43

Ticket 39 stays blocked on ticket 16's pipelined engine run.

## Worktrees

Implementers work in `/Users/sam/wt-NN` on branch `ticket-NN-*`, cut from the commit this
file was added in. Merge their branches into `phase1-metal-d700-optimization` before
removing the worktrees.

## The number that must never be republished

`7.13 ± 0.21 ms/GB` with the secants "1.3σ apart" is the mislabelled-sigma artifact from
Revision 4. It is withdrawn. The interior secants are 2.68σ apart and their mean is
forbidden by rule 3's corollary, so no rate is published for that window.
