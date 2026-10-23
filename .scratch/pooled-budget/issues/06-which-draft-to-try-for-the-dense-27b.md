# 06: Which draft to try for the dense 27B

Type: grilling
Status: resolved
Blocked by: 05

## Question

Which draft, if any, gets a measured trial on the dense 27B, with the target on the host and
the draft on the non-display card?
- (a) download a Qwen3.5 0.8B. This needs the user's approval, and its tokenizer must then be
  checked against the target's;
- (b) quantise Qwythos-9B, already on disk, to fit one card;
- (c) drop drafts and leave dense models bigger than VRAM at the host rate.

The trial's gate also has to show what the per-round checkpoint costs when the target is in
host RAM.

## Answer

(b), decided by the user on 2026-10-23: quantise Qwythos-9B, which is already on disk, and
give it a measured trial as the draft. The 27B target stays on the host, and the draft sits on
the non-display card.
- **Quant: Q3_K_M**, about 4.1 GiB. Q4_K_M would be about 5 GiB, which with the draft's cache
  is too tight for one 6 GB card.
- **Who does it:** the work is delegated to OpenCode. The orchestrator verifies the gate.
