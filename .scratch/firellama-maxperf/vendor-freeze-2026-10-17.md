# Vendored-tree freeze, 2026-10-17

Captured because vendor/llama.cpp is a nested repo detached at the pin with
uncommitted changes, is not tracked by the firellama repo, and a rebuild on top
of it would destroy the only copy.

- pin: `d81235049384534c167caea52b85a694f6103d14`
- tracked files modified: 122
- untracked files: 17
- delta patch: `vendor-delta-2026-10-17.patch`
- untracked archive: `vendor-untracked-2026-10-17.tgz`
- untracked list: `vendor-untracked-2026-10-17.txt`

Reconstruct: clean checkout of the pin, then `git apply` the delta patch, then
unpack the archive over it.

## Known limitation

This is a capture, not a proof. Whether the tree equals pin + the 38-patch series
is untested: the reverse-check that was run (each patch against the final tree)
cannot pass for any patch a later patch touches, so its 25 failures mean nothing.
The valid test is forward replay from a clean pin, or reverse-apply in reverse order.

## Fingerprints

```
vendor-delta-2026-10-17.patch
vendor-untracked-2026-10-17.tgz
```
