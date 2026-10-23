# The dense 27B on the host, on one card, and across both cards

Date: 2026-10-22. Question from the user: can a dense model too big for the cards use both
D700s and the 64 GB together?

## Method

- Engine: `vendor/llama.cpp/build-static/bin/llama-server`, llama.cpp `d81235049` plus the
  51-patch series (including 0046). Built with `TOSH_AVX1=1`; 0 AVX2/FMA mnemonics.
  sha256 21e642e5….
- Model: DavidAU `Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf`. Dense, arch qwen35,
  64 layers, 20.86 GiB.
- Launch: `-c 4096 -t 12 -fa auto --load-mode none --cache-ram 2048 --parallel 1` with
  `TOSH_FA_AMD=1`, plus a per-cell placement:

  | cell | placement |
  |---|---|
  | host | `-ngl 0`, `GGML_METAL_DEVICES=1` |
  | one12 | `-ngl 12`, `GGML_METAL_DEVICES=1` |
  | two24 | `-ngl 24 --split-mode layer`, `GGML_METAL_DEVICES=2` |
  | two28 | `-ngl 28 --split-mode layer`, `GGML_METAL_DEVICES=2` |

- Card buffers, from the load check (`dense_fit.sh`):

  | cell | MTL0 | MTL1 |
  |---|---|---|
  | one12 | 4562 MiB | — |
  | two24 | 3574 MiB | 4562 MiB |
  | two28 | 4175 MiB | 5154 MiB |

  Both cards hold weights in the two-card cells, so the split is in effect. 28 layers is
  as much as two cards hold at this context.
- Requests are greedy (`temperature 0`, `seed 1234`, `cache_prompt false`):
  - short: "Explain what a binary search tree is.", 128 tokens out;
  - mid: 2500 characters of README.md, 856 prompt tokens, 16 tokens out.
- Order: two rounds of host → one12 → two24 → two28. Each cell starts a fresh server, sends
  1 warmup and 2 measured requests per kind, and the warmup is discarded. N = 4 per cell
  and kind.
- No other model server was running (the launchd job was booted out).

## Rows (tok/s, mean and sd over N = 4)

| cell | short decode | short prompt | mid decode | mid prompt (856 tok) | the answer |
|---|---|---|---|---|---|
| host | 2.0258 (0.0141) | 2.7129 (0.0418) | 1.9983 (0.0086) | 5.9722 (0.0139) | coherent |
| one12 | 2.0916 (0.0315) | 3.0230 (0.0242) | 2.0619 (0.0261) | 6.3828 (0.0544) | coherent, same opening as host |
| two24 | 2.1259 (0.0015) | 3.2917 (0.0785) | 2.1032 (0.0025) | 7.0023 (0.0172) | **zeros** |
| two28 | 2.1616 (0.0011) | 3.3817 (0.0339) | 2.1305 (0.0045) | 7.2423 (0.0054) | **zeros** |

## Reading

- **Both two-card cells answer with zeros**: in all 24 responses, and both rounds, the
  text turns to `0000…` after the first token ("Here0000…"). Their throughput is the rate
  of a wrong computation, so it is not a result. This is ticket 68's symptom on the fork's
  own engine, and the trigger is a dense model split across both cards with the rest on
  the host. It is not specific to the shipped 0.87.26 build.
- **One card is coherent.** It differs from the host by 0.0658 tok/s on short decode,
  against sds of 0.0141 and 0.0315, with N = 4 per cell. Mid prompt is 6.3828 against
  5.9722. With a quarter of a dense model on the card, the CPU still computes most of
  each token, and decode stays near 2 tok/s either way.
- So the dense rule stays as it is: a dense model that does not fit runs on the host. A
  one-card partial offload is coherent but differs from the host by about 0.07 tok/s, and
  that does not justify a new placement. The two-card partial offload is wrong, not slow.

## Cannot be run

- A two-card layer split of the dense 27B with the remaining layers on the host gives
  zeros at `-ngl 24` and `-ngl 28`. It is untested whether a model that fits entirely on
  the two cards does the same. Ticket 68 tracks this.
