# 17: Finish the retraction cascade

**What to build:** No derived quantity from the rejected fit survives on any published surface. The decomposition was withdrawn from the local note but the retraction is local, and at least one published surface has not been checked. The rule is cascade: killing a slope kills everything computed from it, including any ceiling that was quoted from the same fit.

**Blocked by:** None (can start immediately).

**Status:** done 2026-10-17 — both published surfaces are clean.

- [ ] Every published surface is checked for each withdrawn figure by direct search, and the list of surfaces checked is recorded
- [ ] Any surviving derived figure is removed together with anything computed from it, in one edit
- [ ] The surfaces that remain unchanged are recorded as checked-and-clean, so the check is not repeated
- [ ] The measured removable component is present wherever the withdrawn figures were removed from

## Result

**Local note (`dist/beta24-notes.md`, committed a0dae6d):** clean. The only occurrences of any withdrawn figure are inside the retraction text that names them, which is deliberate. The 94.6 slope, the 80/20 share, the 23.1 ms intercept and every ceiling computed from them are gone, along with the sentence that described the flash-attention mechanism that cannot exist.

**Published release body, tag `v0.87.24-beta.1`, 21082 characters:** clean. Searched by direct string match for each withdrawn figure — none present. One hit for "weight traffic" is in the speculative-decoding passage and refers to a byte fraction of a Q6_K model, which is a different quantity and was never withdrawn.

**Independent clone views of the repo docs (`origin/main` 8a238c4):** these do not carry the decomposition at all, because it was never committed to a tracked doc before the retraction. The relayed report that `origin/main`'s note "contains no 94.6, no 80/20, no unidentified" is consistent with that: the derived work lived in the gitignored release notes and in the release body, and both are now clean.

Nothing further to remove. The measured removable component — the collective at 4.5–5.6 ms against a verified control — is present in the note.
