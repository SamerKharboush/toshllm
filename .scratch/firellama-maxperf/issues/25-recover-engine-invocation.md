# 25: Recover or declare unrecoverable the engine invocation

**What to build:** A command line requested earlier was never delivered, and the harness that produced it is no longer on disk. This ticket ends in either the exact invocation or a plain statement that it cannot be recovered, because a number without its invocation is not reproducible.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Every plausible location for the harness is searched, and the search is recorded
- [ ] If recovered, the exact invocation is recorded with the model, the prompt length and the window
- [ ] If not recovered, that is stated plainly and any published figure depending on it is marked as lacking an invocation
- [ ] The outcome is recorded where the figure is published, not only in the working notes
