# 05: A draft model for the dense 27B on the host

Type: research
Status: claimed
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
