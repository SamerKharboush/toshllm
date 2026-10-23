# 05: A draft model for the dense 27B on the host

Type: research
Status: resolved
Blocked by:

## Question

Which models in /Users/sam/models could serve as a speculative-decoding draft for the dense
Qwen3.6-27B?
- their vocabulary and tokenizer must match;
- give each one's size and quant.

Then check, from this fork's source and upstream docs, whether the engine's `--spec-type`
and draft options work when the target runs on the host (`-ngl 0`). Can the draft sit on a
card while the target stays in RAM?

Dense models bigger than VRAM run at about 2 tok/s, and placing layers on the cards changes
that by about 0.07 tok/s. A draft model is the only lever named so far.

## Answer

No small model on disk can draft for the 27B.
- **The Qwen3 small models are out.** They have a different vocabulary: 151,936 tokens against
  248,320, with text differing from id 280, and the engine allows a size difference of at
  most 128.
- **Exact tokenizer matches on disk** (all three hashes equal, 0 differing ids):
  - Qwythos-9B, BF16, 17.92 GB. It would need quantising to fit a card.
  - Ternary-Bonsai-2-27B PQ2_0, 7.21 GB. It has a 27B shape and is a different base, and it
    does not fit one card.
  - Three more, all 17–30 GB.
- **Not on disk:** a Qwen3.5 0.8B. Upstream PR #22358 says it is vocab-compatible with
  Qwen3.6 27B, and it is the right size for a draft.
- **Engine, from source only, not run:** `--spec-type draft-simple` takes a separate draft.
  The draft has its own `-ngld`/`-devd`, so it can sit on a card while the target runs with
  `-ngl 0` (`common/speculative.cpp:3083-3097`).
- **Two unmeasured costs:**
  - a full checkpoint save and restore per draft round, because the target is a hybrid
    recurrent model (`tools/server/server-context.cpp:3355-3378`);
  - the TOSH plan reserves no VRAM for a draft model.

Detail: branch `research/a-draft-model-for-the-dense-27b`, file
`research/a-draft-model-for-the-dense-27b.md` (commit fcdb6e6, not pushed).
