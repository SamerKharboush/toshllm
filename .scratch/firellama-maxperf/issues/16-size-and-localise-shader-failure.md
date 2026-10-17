# 16: Size and localise the shader failure

**What to build:** Every server start on this machine prints a Metal shader compilation failure. It is present in both arms of every differential experiment, which makes every patched-versus-pristine delta on record a comparison of two substituted builds. This is the only open item that can retroactively invalidate published numbers, and it is the only one that survives a fresh checkout. The ticket ends with either a size for its share of a decode window or a statement that it is off the decode path.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The failure is localised from the compiler's own error text, giving a source file and line, rather than inferred from the engine's flattened error string
- [ ] The kernel that fails to compile is named, and whether something substitutes for it at runtime is stated
- [ ] One measurement sizes the failed path's share of a decode window, or states that it does not appear in it
- [ ] The finding says whether any published figure must be re-flagged as measured against a substituted build
- [ ] A note records the fingerprint of the shader binaries the current numbers were measured with
