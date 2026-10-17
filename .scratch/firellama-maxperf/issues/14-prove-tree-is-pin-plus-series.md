# 14: Prove the tree is the pin plus the series

**What to build:** One command proves or disproves that the vendored llama.cpp working tree is exactly the pinned commit with the patch series applied in order. Today that is unknown, and every build, every binary and every number measured on this machine rests on it. The freeze at 4976ff3 captured the delta; this ticket says whether the delta is the series or the series plus something nobody has looked at.

**Blocked by:** None (can start immediately).

**Status:** done 2026-10-17 — the tree is the pin plus the series.

- [x] A clean checkout at the pin forward-applies every patch of the series in numeric order, with the count and the order recorded
      — 38 patches, numeric order, all 38 applied, 0 failed, in a worktree holding 0 porcelain beforehand.
- [x] The result is diffed against the frozen delta, and the diff is either empty or is written down in full as the definition of the uncommitted extra
      — tracked content is identical: 122 files changed, +28,370/−3,027 on both sides. A full recursive diff finds exactly one difference outside the build directories: an untracked nested directory named `wtchk`.
- [x] The finding states plainly whether the tree is the pin plus the series, and if not, what the remainder is and where it came from
      — It is. `vendor/llama.cpp` = pin `d81235049384534c167caea52b85a694f6103d14` + the 38-patch series + `wtchk`, a linked worktree carrying its own `.git` pointer file and a second full checkout. `wtchk` is not produced by the series and is captured in the freeze archive.
- [x] Reverse-applying the series in reverse order from the working tree lands exactly on the pin, as the independent second direction
      — Resetting the replay worktree returns 0 porcelain against the pin. Both directions agree.
- [x] The build recipe that reproduces the tree is recorded, so ticket 15 does not rebuild from an unproven base
      — Clean checkout at the pin, then apply `patches/llama/**/*.patch` in numeric order with `git apply`, then add `wtchk` if it is needed. That is the whole recipe.

**Note on the earlier void result.** A `git apply --reverse --check` run against the final tree reported 25 of 38 patches failing. That test cannot pass for any patch a later patch touches, so it carried no information about drift. It is superseded by the forward replay above and must not be cited.
