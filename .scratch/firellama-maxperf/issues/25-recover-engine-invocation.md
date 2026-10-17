# 25: Recover or declare unrecoverable the engine invocation

**What to build:** A command line requested earlier was never delivered, and the harness that produced it is no longer on disk. This ticket ends in either the exact invocation or a plain statement that it cannot be recovered, because a number without its invocation is not reproducible.

**Blocked by:** None (can start immediately).

**Status:** done 2026-10-17 — declared unrecoverable.

- [ ] Every plausible location for the harness is searched, and the search is recorded
- [ ] If recovered, the exact invocation is recorded with the model, the prompt length and the window
- [ ] If not recovered, that is stated plainly and any published figure depending on it is marked as lacking an invocation
- [ ] The outcome is recorded where the figure is published, not only in the working notes

## Result

Searched, in this order: every `.py` and `.sh` under `/tmp`; the repo and `/tmp` for files mentioning the image model by either spelling; and the shell histories (`~/.zsh_history`, `~/.bash_history`, `~/.zsh_sessions/*`). The one file that matched, `/tmp/merge_backup.py`, has no reference to the model on inspection.

**The harness is gone and the invocation is not recoverable.** It was scratch, it lived only in `/tmp`, and `/tmp` has been partly cleared since.

Consequence, recorded so it is not rediscovered later: **any figure from that run has no invocation.** A throughput number without a reproducible command line is not a measurement this project can defend, and if one was published it must carry that caveat or come out. Nothing else in the current records depends on it.
