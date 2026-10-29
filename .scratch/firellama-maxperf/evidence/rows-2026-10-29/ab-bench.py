#!/usr/bin/env python3
"""Engine-neutral decode/prefill timing over an OpenAI-compatible streaming endpoint.

Usage: ab-bench.py <base_url> <model> <api_key|-> <label> <runs> <out.jsonl>
The same client clock times both engines: TTFT from request to the first content
delta, decode rate from (n_chunks - 1) / (t_last - t_first). Request 1 is a warmup
and is recorded with warmup=true.
"""
import json, sys, time, urllib.request

base, model, key, label, runs, out = sys.argv[1:7]
PROMPT = ("Write a Python function that inserts a key into a binary search tree "
          "and explain how it works.")
MAX = 128

def one(i):
    body = json.dumps({"model": model, "stream": True, "temperature": 0, "top_k": 1,
                       "max_tokens": MAX, "messages": [{"role": "user", "content": PROMPT}],
                       "stream_options": {"include_usage": True}}).encode()
    req = urllib.request.Request(base.rstrip("/") + "/chat/completions", body,
                                 {"Content-Type": "application/json"})
    if key != "-":
        req.add_header("Authorization", "Bearer " + key)
    t0 = time.monotonic(); stamps = []; text = []; usage = None
    with urllib.request.urlopen(req, timeout=1800) as r:
        for raw in r:
            line = raw.decode().strip()
            if not line.startswith("data:") or line == "data: [DONE]":
                continue
            d = json.loads(line[5:])
            if d.get("usage"):
                usage = d["usage"]
            for c in d.get("choices", []):
                delta = c.get("delta", {})
                piece = (delta.get("content") or "") + (delta.get("reasoning_content") or "")
                if piece:
                    stamps.append(time.monotonic()); text.append(piece)
    n = len(stamps)
    rec = {"label": label, "run": i, "warmup": i == 0, "chunks": n,
           "ttft_s": stamps[0] - t0 if n else None,
           "decode_tok_s": (n - 1) / (stamps[-1] - stamps[0]) if n > 1 else None,
           "completion_tokens": usage and usage.get("completion_tokens"),
           "text": "".join(text)}
    return rec

with open(out, "a") as f:
    for i in range(int(runs)):
        rec = one(i)
        f.write(json.dumps(rec) + "\n"); f.flush()
        print(label, i, rec["chunks"], round(rec["ttft_s"] or 0, 3),
              round(rec["decode_tok_s"] or 0, 4), repr(rec["text"][:60]), flush=True)
