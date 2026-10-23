# 08: The Qwythos-9B draft trial

Type: task
Status: resolved
Blocked by: 06

## Question

With the Qwythos-9B Q3_K_M draft on the non-display card and the dense 27B target at
`-ngl 0`, what are the decode and prompt rates against the host-only row? Is the text
coherent and does it open like the host's?

The host-only row is 2.0258 tok/s short decode (sd 0.0141, N = 4), from
`.scratch/firellama-maxperf/evidence/the-dense-27b-across-host-one-card-and-both-cards-2026-10-22.md`.

Also record:
- the draft acceptance rate;
- the checkpoint cost per draft round, if the engine logs it.

## Answer

The draft is slower:
- with the draft: 1.3299 tok/s short decode (sd 0.0109, N = 4);
- host only, same session: 1.9423 (sd 0.0284).

The 27B accepted 64% of drafted tokens, a mean of 2.89 per verify round. Each round costs
about four host tokens. The draft really was on card 1 (33/33 layers, 3982 MiB on MTL0). The
text is coherent and opens like the host's.

Evidence: `../../firellama-maxperf/evidence/a-draft-model-for-the-dense-27b-on-the-host-2026-10-23.md`.
