# 24: Record the disqualifications

**What to build:** Models that cannot answer the question are written down with their reasons, so they stop being re-proposed as candidates. Two are currently in that position for reasons that are not obvious from their names or sizes.

**Blocked by:** None (can start immediately).

**Status:** done 2026-10-17 — verified from the model header.

- [ ] The recurrent-hybrid model is recorded as unusable for a depth comparison, with the structural reason stated rather than the conclusion alone
- [ ] The image model is recorded as lacking the header fields a text-model comparison needs
- [ ] Any model whose documentation cites patches that are not present in the series is recorded as such
- [ ] Each entry names what would have to change for it to become usable

## Result

### Ternary-Bonsai-2-27B-PQ2_0 — unusable for a depth comparison

Verified from its own GGUF header, not from the documentation that recommends it:

```
qwen35.full_attention_interval = 4
qwen35.ssm.conv_kernel = 4      qwen35.ssm.state_size = 128
qwen35.ssm.group_count = 16     qwen35.ssm.time_step_rank = 48
qwen35.ssm.inner_size = 6144
qwen35.attention.head_count = 24   head_count_kv = 4
```

64 blocks with a full-attention interval of 4 means **16 blocks perform full attention and 48 are SSM/recurrent.** Its 64 layers against the measured 14B's 40 is therefore not a depth axis for attention: the quantity that any per-token attention or KV term would scale with is 16, not 64. Against the 14B that is depth −60%, not depth +60%.

Three further disqualifiers: it is a third quantisation family, so its dequantisation cost per byte differs from both of the measured cells; it carries a recurrent state that moves per token; and the fork documentation that recommends it cites patches 0079 and 0080, **neither of which exists anywhere in the series** (verified — `find patches -name '*0079*' -o -name '*0080*'` returns nothing).

Net information about width versus depth: **zero**. One equation, one unknown.

What would have to change: a model with the same quantisation family as the measured cells, a pure attention stack, and no recurrent state.

### qwen-image-2.1-UC-Q8_0 — not a text model

297 tensors and none of the standard text-model header keys (`block_count`, `embedding_length`, `head_count` all absent). It is an image model and cannot enter a per-token decode comparison at all.

### Rule this establishes

A model's documentation is not evidence that it can answer the question. Read the header before spending a run: block count, width, head count, attention interval, and whether the architecture carries recurrent state.
