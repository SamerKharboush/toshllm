# 06: Which draft to try for the dense 27B

Type: grilling
Status: open
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
