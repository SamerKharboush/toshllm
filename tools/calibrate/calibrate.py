#!/usr/bin/env python3
"""Calibration harness.

Establishes the measurement noise floor that tools/fitgate.py uses as its
denominator. One row per measured invocation, so the sigma is invocation to
invocation, which is the way a single measurement is actually taken.

Why separate processes and not `llama-bench -r 20`: repetitions inside one
process share a thermal and allocator state, and this machine has been observed
to sit in discrete states a few percent apart that flip every 5 to 15 blocks. A
within-process sigma would hide exactly that. The script reports both anyway,
because the difference between them is itself informative.

usage:
  calibrate.py --cells cells.json --out calib.csv [--warmup 3] [--reps 20]
"""

import argparse
import csv
import json
import os
import statistics
import subprocess
import sys
import time


def load_cells(path):
    with open(path) as f:
        cfg = json.load(f)
    for key in ("binary", "cells"):
        if key not in cfg:
            raise SystemExit(f"{path}: missing '{key}'")
    cfg.setdefault("env", {})
    cfg.setdefault("pp", 512)
    cfg.setdefault("tg", 128)
    cfg.setdefault("reps_per_invocation", 2)
    return cfg


def run_once(cfg, model, timeout):
    """One llama-bench invocation, returned as {test: t_s}."""
    cmd = [
        cfg["binary"], "-m", model,
        "-p", str(cfg["pp"]), "-n", str(cfg["tg"]),
        "-r", str(cfg["reps_per_invocation"]),
        "-o", "csv",
    ] + list(cfg.get("extra_args", []))
    env = dict(os.environ)
    env.update(cfg["env"])
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(
            f"llama-bench failed ({p.returncode}) for {model}\n"
            f"{(p.stderr or p.stdout)[-800:]}"
        )

    lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
    # this fork's csv header starts with build_commit, not model
    header_i = next((i for i, ln in enumerate(lines) if ln.startswith("build_commit,")), None)
    if header_i is None:
        raise RuntimeError(f"no csv header in llama-bench output:\n{p.stdout[-800:]}")

    reader = csv.DictReader(lines[header_i:])
    out = {}
    for row in reader:
        try:
            n_prompt = int(row.get("n_prompt") or 0)
            n_gen    = int(row.get("n_gen") or 0)
        except ValueError:
            continue
        # there is no 'test' column; the test is identified by these two
        if n_prompt <= 0 and n_gen <= 0:
            continue
        test = f"pp{n_prompt}" if n_prompt > 0 else f"tg{n_gen}"
        raw = (row.get("avg_ts") or "").strip()
        if not raw:
            continue
        out[test] = float(raw)
        sd = (row.get("stddev_ts") or "").strip()
        out[test + "_sd"] = float(sd) if sd else 0.0
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cells", required=True)
    ap.add_argument("--out", required=True, help="raw per-invocation csv")
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--reps", type=int, default=20)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--settle", type=int, default=0,
                    help="seconds of idle before measuring")
    args = ap.parse_args()

    cfg = load_cells(args.cells)

    print(f"binary   : {cfg['binary']}")
    print(f"env      : {cfg['env']}")
    print(f"warmup   : {args.warmup} discarded, then {args.reps} measured")
    print(f"cells    : {len(cfg['cells'])}")
    for c in cfg["cells"]:
        if not os.path.exists(c["model"]):
            raise SystemExit(f"model not found: {c['model']}")

    if args.settle:
        print(f"settling : {args.settle}s idle")
        time.sleep(args.settle)

    rows = []
    for cell in cfg["cells"]:
        label, model = cell["label"], cell["model"]
        for i in range(args.warmup):
            print(f"  warmup {label} {i + 1}/{args.warmup}", flush=True)
            run_once(cfg, model, args.timeout)
        for i in range(args.reps):
            t0 = time.time()
            got = run_once(cfg, model, args.timeout)
            rows.append({"cell": label, "rep": i, "seconds": round(time.time() - t0, 1), **got})
            print(f"  {label} rep {i + 1}/{args.reps}: " +
                  " ".join(f"{k}={v:.3f}" for k, v in got.items()), flush=True)

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nraw csv -> {args.out}")

    tests = sorted({k for r in rows for k in r
                    if k not in ("cell", "rep", "seconds") and not k.endswith("_sd")})
    print("\nper cell, across invocations:")
    summary = {}
    for cell in cfg["cells"]:
        label = cell["label"]
        for test in tests:
            vals = [r[test] for r in rows if r["cell"] == label and test in r]
            if len(vals) < 2:
                continue
            mean = statistics.mean(vals)
            sigma = statistics.stdev(vals)
            within = statistics.mean([r.get(test + "_sd", 0.0) for r in rows
                                      if r["cell"] == label and test in r])
            summary.setdefault(label, {})[test] = (mean, sigma)
            print(f"  {label:<12} {test:<8} mean {mean:8.3f}  "
                  f"sigma {sigma:6.4f}  CV {100 * sigma / mean:5.2f}%  "
                  f"within-run sd {within:6.4f}  n={len(vals)}")
            if within > 0 and sigma > 3 * within:
                print(f"  {'':<12} {'':<8} ^ between-invocation spread is "
                      f"{sigma / within:.1f}x the within-run spread")

    print("\nnoise floor for the gate (sigma in t/s, one number per cell/test):")
    print(json.dumps({c: {t: round(s, 6) for t, (m, s) in v.items()}
                      for c, v in summary.items()}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
