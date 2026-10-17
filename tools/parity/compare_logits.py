#!/usr/bin/env python3
"""Compare two logit dumps written by logitprobe.

Reports max abs difference, per-position cosine similarity, and top-1
agreement. The token ids and vocab size must match, so a difference can only
come from the forward pass and not from different inputs.

exit 0 = within the given tolerance, exit 1 = not.
"""

import argparse
import math
import struct
import sys

MAGIC = b"LOGP"


def read_dump(path):
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:4] != MAGIC:
        raise SystemExit(f"{path}: not a logitprobe dump")
    n_vocab, n_tok = struct.unpack_from("<ii", blob, 4)
    off = 12
    tokens = struct.unpack_from(f"<{n_tok}i", blob, off)
    off += 4 * n_tok
    have = (len(blob) - off) // 4
    if have != n_tok * n_vocab:
        raise SystemExit(
            f"{path}: truncated, expected {n_tok * n_vocab} floats, found {have}"
        )
    logits = struct.unpack_from(f"<{n_tok * n_vocab}f", blob, off)
    return n_vocab, n_tok, tokens, logits


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0.0 or nb == 0.0:
        return float("nan")
    return dot / (na * nb)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base", help="reference dump (the CPU oracle)")
    ap.add_argument("test", help="dump under test (the GPU fork)")
    ap.add_argument("--max-abs", type=float, default=1e-5)
    ap.add_argument("--min-cosine", type=float, default=0.9999)
    args = ap.parse_args()

    nb, ntb, tb, lb = read_dump(args.base)
    nt, ntt, tt, lt = read_dump(args.test)

    if nb != nt:
        print(f"FAIL: vocab differs, {nb} vs {nt}")
        return 1
    if ntb != ntt:
        print(f"FAIL: token count differs, {ntb} vs {ntt}")
        return 1
    if tb != tt:
        print(f"FAIL: token ids differ\n  base: {tb}\n  test: {tt}")
        return 1

    print(f"vocab {nb}, {ntb} tokens, identical token ids in both dumps")

    worst_abs = 0.0
    worst_pos = -1
    worst_cos = 1.0
    disagree = 0

    for i in range(ntb):
        pb = lb[i * nb:(i + 1) * nb]
        pt = lt[i * nb:(i + 1) * nb]
        d = max(abs(x - y) for x, y in zip(pb, pt))
        c = cosine(pb, pt)
        if d > worst_abs:
            worst_abs, worst_pos = d, i
        worst_cos = min(worst_cos, c)
        if max(range(nb), key=pb.__getitem__) != max(range(nb), key=pt.__getitem__):
            disagree += 1

    print(f"max abs diff     : {worst_abs:.6g}  (at position {worst_pos})")
    print(f"min cosine       : {worst_cos:.10f}")
    print(f"top-1 mismatches : {disagree} / {ntb}")

    ok = worst_abs <= args.max_abs and worst_cos >= args.min_cosine and disagree == 0
    print(f"thresholds       : max abs <= {args.max_abs:g}, cosine >= {args.min_cosine:g}, 0 mismatches")
    print("VERDICT: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
