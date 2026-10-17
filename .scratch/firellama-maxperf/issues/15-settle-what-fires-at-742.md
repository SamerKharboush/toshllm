# 15: Settle what fires at 742

**What to build:** One rebuild and one reproduction turn a two-way uncertainty into a fact. The binary aborts claiming line 742 of the tensor-split backend; the pin has the mul_mat abort at 609 and a reshape abort at 744; the working tree routes the mul_mat message through a naming helper at 781. Whichever literal the rebuilt binary prints decides whether the deployed binary was a partially patched build or whether an unpatched site fires in the product. Until this settles, llama-bench is not usable as the second timing arm.

**Blocked by:** 14 (done 2026-10-17 — the tree is the pin plus the series).

**Status:** ready-for-agent — recipe recovered.

- [ ] The build tree is rebuilt from the proven recipe, and the rebuilt llama-bench postdates the source it was built from
- [ ] The tensor-split abort is reproduced and the first stderr line is captured verbatim, message text included, not just the line number
- [ ] The finding names which source literal fired and says whether the previously measured abort came from a stale build or from a defect in the product
- [ ] The same configuration is run through llama-server to confirm the named-exit path is reachable there
- [ ] A note records that the binary which produced all previously measured numbers is no longer the binary in the tree

## Build recipe, recovered from the last build's cache

From `vendor/llama.cpp/build-static/CMakeCache.txt`:

- `CMAKE_GENERATOR` = Unix Makefiles, out-of-source into `build-static`
- `CMAKE_BUILD_TYPE` = Release
- `CMAKE_OSX_ARCHITECTURES` = x86_64
- `GGML_METAL=ON`, `GGML_BLAS=ON`, `GGML_ACCELERATE=ON`, `GGML_CPU_REPACK=ON`, `GGML_CPU=ON`, `BUILD_TESTING=ON`

The previous build's log (`/tmp/ab/build-0038.log`) is compiler output only, so the configure line is reconstructed from the cache rather than read from a script. Confirm against the cache before running.

## What the rebuild must produce

A `llama-bench` whose mtime postdates `ggml/src/ggml-backend-meta.cpp`. The current binary is Oct 15 21:49:58 against a source of Oct 16 01:23:35, which is why the abort reports line 742 while the source holds the message at 781.
