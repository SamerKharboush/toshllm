# Speculative decoding with the draft on the second card: it fires, and it loses

## The gate

T2's answer is that the second D700 exists and is not enrolled by default:
`GGML_METAL_DEVICES=2 GGML_METAL_DEVICE_LIST=0,1` registers it, and the backend then names
the devices `MTL0` and `MTL1`. The gate is open, so the cell is measured.

## The 35B cell cannot be measured on this machine

The engine refuses the draft model:

```
E common_speculative_init_result: the target and draft vocabs are not compatible
E srv load_model: failed to initialize speculative decoding context: draft model vocab
  type must match target model to use speculation
```

The server does not stop. It starts without a draft and answers normally, and the response
carries no draft counters at all:

| cell | decode tok/s | draft_n | draft_n_accepted |
|---|---|---|---|
| 35B, `--spec-draft-model Qwen3-0.6B-Q8_0.gguf --spec-draft-device MTL1` | 0.1486 (n=2) | 0 | 0 |
| 35B, no draft flags | 0.1450 (n=2) | 0 | 0 |

The target is a `qwen35moe` and every draft model on this machine is a Qwen3 with a
different vocabulary, so there is no draft that the 35B accepts. The 35B's speculative
decoding is gated on a Qwen3.5 draft that is not on this box, and the cell above is what a
rejected draft looks like: the same speed as no draft and nothing drafted.

## The 8B cell, which is the mechanism

Qwen3-8B-Q4_K_M target, Qwen3-0.6B-Q8_0 draft, `--spec-type draft-simple
--spec-draft-n-max 8`, 64 generated tokens, temperature 0, n=3, the target on `MTL0` in
every cell.

| cell | decode tok/s | sd | drafted | accepted | acceptance |
|---|---|---|---|---|---|
| draft on `MTL1` (the second card) | 2.6250 | 0.0040 | 138 | 45 | 32.6% |
| draft on `MTL0` (the target's card) | 2.5168 | 0.0013 | 138 | 45 | 32.6% |
| no draft | 8.3239 | 0.0048 | 0 | 0 | - |

**Speculative decoding fires.** 138 tokens were drafted and 45 of them were accepted, the
same 45 in every trial.

**It is 3.17x slower than not drafting.** The target's decode on this card is 8.32 tok/s
and the speculative decode is 2.63. The acceptance rate is not the problem: the draft is
right often enough, and the target still has to verify every drafted token.

**The second card is worth 4.3% to the draft.** The same draft on `MTL1` instead of `MTL0`
gives 2.6250 against 2.5168 tok/s, 5.9 standard deviations apart on their own spreads. The
card that the draft sits on does not decide whether speculative decoding is worth it.

## What this means

The spec's cell is "the draft on B, the target on A". On this machine that cell is
measured, it fires, and it loses to the target alone by 3.17x, whether the draft has the
second card to itself or shares the target's. The honest summary is the one the spec
offers for the gated case: **gated on dual-device; the draft fires at a 32.6% acceptance
rate and the decode is 3.17x slower than not drafting.**

The 35B keeps its own answer: the cell is not measurable without a Qwen3.5 draft, and the
35B is a model whose decode is 76.6x faster on the CPU than on the card, which is a bigger
fact for that model than any draft.
