# 27: Which kernel executes decode attention

**What to build:** the identity of the kernel that actually computes decode attention on this builder, given that the AMD wave64 dk128 f16 variant fails to compile and its failure is returned in the shape of a success with a nil pipeline. Until this is answered, no published decode delta can be classified as clean or as contaminated, because the substitute is unknown.

**Blocked by:** 16 (partial — the failing kernel is named).

**Status:** ready-for-agent

- [ ] The dispatch site for flash attention is read, and whether it guards on a nil pipeline is stated from the code
- [ ] If it guards, the path taken instead is named, and whether that path is a different GPU kernel or host-side work
- [ ] If it does not guard, that is stated plainly, with what a nil pipeline with zero threadgroup dimensions does when encoded
- [ ] A runtime observation confirms the code reading, rather than the code reading standing alone
- [ ] The finding states which published decode figures were produced with a substitute in the path and which were not
- [ ] The fork's own rule is applied to the conclusion: a success that silently returns wrong data has no fallback
