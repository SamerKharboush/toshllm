# A draft model for the dense 27B on the host

Date: 2026-10-23. Ticket: `.scratch/pooled-budget/issues/08-the-qwythos-draft-trial.md`.
The script was written and run by OpenCode (`opencode/glm-5.3-flash-free`). The numbers,
placement and text below were checked by the orchestrator.

## Method

- Engine: fork engine `d81235049` + 52 patches (0047 included), AVX1. sha256 ebacf72b….
- Target: DavidAU Qwen3.6-27B Q6_K (dense, qwen35, 64 layers, 20.86 GiB) at `-ngl 0`.
- Draft: Qwythos-9B Q3_K_M, 4.31 GiB, sha256 eaba03d8….
  - Quantised here from the BF16 original.
  - Its tokenizer hash equals the target's: gpt2, 248,320 tokens.
- Launch: `-c 4096 -t 12 -fa auto --load-mode none --cache-ram 2048 --parallel 1` with
  `TOSH_FA_AMD=1 GGML_METAL_DEVICE_INDEX=1`, which exposes the non-display card as MTL0.
  - The draft cell adds `-md <draft> --spec-type draft-simple -ngld all -devd MTL0`.
- Placement, from a separate load check at `-lv 4`:
  - the target is on the CPU: offloaded 0/65, CPU model buffer 21348.16 MiB;
  - the draft is on the card: offloaded 33/33, MTL0_Private model buffer 3982.08 MiB, KV
    128 MiB, compute 216.17 MiB.
- Requests, greedy, `cache_prompt false`:
  - short: the BST prompt, 128 tokens out;
  - mid: 2500 characters of README.md, 856 prompt tokens, 16 tokens out.
- Order: host, draft, host, draft. Each run starts a fresh server; request 1 of each kind is
  a warmup and is discarded. N = 4 per cell and kind.

## Rows (tok/s, mean and sd)

| cell | short decode | short prompt | mid decode | mid prompt |
|---|---|---|---|---|
| host | 1.9423 (0.0284) | 2.5869 (0.0420) | 1.9508 (0.0089) | 5.7208 (0.0084) |
| host + draft on card 1 | 1.3299 (0.0109) | 2.2389 (0.0063) | 1.3261 (0.0390) | 4.9028 (0.0782) |

- Draft acceptance on short: 70 accepted of 110 generated (0.63636), a mean of 2.89 tokens
  per verify round. The figure was identical on every request.
- On mid: 8 of 12 (0.66667), a mean of 3.00.
- Text: all 24 responses are coherent, with no run of 20 identical characters. Every
  response's first 60 characters equal the host's for the same request.

## Reading

- The draft makes decode slower: 1.3299 against 1.9423 tok/s on short decode.
- Per verify round, the short request takes about 128 / 2.89 ≈ 44 rounds in 128 / 1.3299 ≈
  96 s, about 2.2 s a round. A single host token takes about 0.51 s. A round costs about four
  host tokens and yields 2.89, so it loses.
- Where the round's time goes (verifying the batch on the CPU, the per-round checkpoint of
  this hybrid recurrent target, or the draft itself) was not split. The arithmetic is from
  the rows above, not a separate measurement.
- For dense models bigger than VRAM, a draft this size does not help on this machine.

## Cannot be run

- A smaller draft with this vocabulary (a Qwen3.5 0.8B) is not on disk.
