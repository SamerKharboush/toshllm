#!/usr/bin/env python3
"""The secant list is the claim: stdout of this script is the published number.

Standard library only. It reads a calibration CSV and prints, for the cells in
ascending size order: every adjacent secant with a sigma propagated from the two
bounding per-cell sigmas, the chi-squared between neighbouring secants, and the
inverse-variance weighted mean with its interval -- but the mean only when the
neighbours agree. If this disagrees with the prose, this wins and the prose is rewritten.

Sigma is keyed to its cell, never to a position in the file. That is the failure this
tool exists to make impossible: a sigma array in CSV-block order rather than table order
reached a claimed 7.13 +/- 0.21 through a review, a challenge and two spec revisions
(spec Revision 4). So every sigma is printed on the row of the cell it was measured on,
and the two bounds' sigmas are columns of the secant row that uses them.

    y    = 1000 / mean(tg128 over the reps)       ms per token
    sig  = (y**2 / 1000) * stdev(tg128 over reps)  ms, the sigma fitgate.py uses

That is the stdev of the per-invocation values, not their standard error: it is the
sigma the measured secants were computed with. Dividing by sqrt(n) would shrink every
sigma 4.5x and report the interior disagreement as 12 sigma instead of 2.69.

Sizes are supplied on the command line as name:bytes, the same shape as fitgate.py's
name:bytes:ms, because the CSV carries names and times but not sizes. x is decimal GB,
bytes / 1e9, taken from the GGUF the cell ran, so nothing is rescaled to make a slope
come out even. A cell named here but absent from the CSV, or in the CSV without a size,
is refused, as is a duplicate name or a zero-width interval.

The mean is refused, not caveated, when neighbouring secants disagree beyond
AGREE_SIGMA. CLAUDE.md rule 3, corollary: two probes that disagree by more than the
noise floor are two observations, not one quantity. A script that computes a forbidden
average and leaves the decision to its reader will eventually be read by someone who
prints it, so the refused mean is never computed and no number reaches stdout. The
limit is a constant, not a flag: a flag would put the decision back in the hands of
whoever runs the tool, and the whole ticket is that it must not be there.

usage:
  ./tools/secant.py --calib tools/calibrate/results/calibration-5cell-2026-10-18.csv \\
      0.6B-Q8_0:639446688 4B-Q4_K_M:2497280256 4B-Q6_K:3306260704 \\
      8B-Q4_K_M:5027783488 14B-Q4_K_M:9001753376

control, the branch where a mean IS licensed (secants equal by construction):
  ./tools/secant.py --calib tools/secant-control-3cell.csv \\
      A:2000000000 B:3000000000 C:4000000000

exit codes, distinct so a caller can tell a refusal from a failed read:
  0  success: neighbours agree and the weighted mean with its interval was printed
  1  MEAN REFUSED: neighbours disagree beyond the noise floor; no mean was printed
  2  malformed input: CLI, CSV, schema version, missing/duplicate/unknown/zero-width cell

The interval on the mean treats the secants as independent; adjacent ones share a cell,
so it is 1 sigma of the weighted mean and not a coverage interval.
"""
import argparse, math, os, statistics, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fitgate import load_calib  # same schema_version guard as the gate, not a copy of it

EXIT_OK, EXIT_REFUSED, EXIT_BAD_INPUT = 0, 1, 2

# Neighbouring secants must agree within this many sigma before a mean is licensed.
# 2.0 is the 95% consistency limit. It is fixed here rather than exposed as a flag, and
# it is below 3 on purpose: at 3 the 2.69 sigma interior pair of the five-cell series
# would be averaged into the rate that Revision 4 withdrew.
AGREE_SIGMA = 2.0


def die(msg):
    print(f"BAD INPUT: {msg}", file=sys.stderr)
    raise SystemExit(EXIT_BAD_INPUT)


def cell_times(path, test):
    """{cell: (y in ms/token, its sigma, n)} from the raw per-invocation rows."""
    try:
        rows = load_calib(path)
    except SystemExit as e:              # unversioned or unknown schema; fitgate refuses it
        die(str(e))
    except OSError as e:
        die(f"{path}: {e}")

    by = {}
    for r in rows:
        raw = (r.get(test) or "").strip()
        if not raw:
            continue
        try:
            by.setdefault(r.get("cell") or "", []).append(float(raw))
        except ValueError:
            die(f"{path}: {test} = {raw!r} is not a number (cell {r.get('cell')!r})")

    out = {}
    for name, vals in by.items():
        if not name:
            die(f"{path}: a row has no cell name")
        if len(vals) < 2:
            die(f"{path}: {name} has {len(vals)} {test} value(s); a sigma needs 2")
        m = statistics.mean(vals)
        if m <= 0:
            die(f"{path}: {name} mean {test} = {m:g}; cannot invert to ms per token")
        y = 1000.0 / m
        out[name] = (y, (y * y / 1000.0) * statistics.stdev(vals), len(vals))
    if not out:
        die(f"{path}: no {test} values")
    return out


def main():
    ap = argparse.ArgumentParser(description="adjacent secants and their sigma from a calibration CSV")
    ap.add_argument("--calib", required=True, help="raw per-invocation calibration CSV")
    ap.add_argument("--calib-test", default="tg128", help="column to take y and sigma from")
    ap.add_argument("cells", nargs="+", metavar="name:bytes", help="cell name:model size in bytes")
    a = ap.parse_args()

    sizes = {}
    for spec in a.cells:
        f = spec.split(":")
        if len(f) != 2:
            die(f"bad cell {spec!r}; want name:bytes")
        name, raw = f
        try:
            b = int(raw)
        except ValueError:
            die(f"bad size {raw!r} for {name!r}; want integer bytes")
        if b <= 0:
            die(f"{name}: size {b} bytes")
        if name in sizes:
            die(f"duplicate cell name {name!r}")
        sizes[name] = b

    cells = cell_times(a.calib, a.calib_test)
    missing = sorted(set(sizes) - set(cells))
    extra = sorted(set(cells) - set(sizes))
    if missing:
        die(f"named here but not in {a.calib}: {missing}")
    if extra:
        die(f"in {a.calib} but no size given: {extra}")
    order = sorted(sizes, key=lambda n: sizes[n])
    for n0, n1 in zip(order, order[1:]):
        if sizes[n0] == sizes[n1]:
            die(f"{n0} and {n1} are the same size; the interval between them is zero-width")

    print(f"calibration {a.calib}   test {a.calib_test}")
    print("x = bytes / 1e9 (GB).  sigma = stdev of the per-invocation values, propagated to ms/token.")
    print()
    print("cells, ascending x; each sigma sits on the row of the cell it was measured on")
    print(f"  {'cell':16s}{'bytes':>13s}{'x_GB':>9s}{'y_ms':>10s}{'sigma_ms':>10s}{'n':>5s}")
    for n in order:
        y, s, k = cells[n]
        print(f"  {n:16s}{sizes[n]:13d}{sizes[n] / 1e9:9.3f}{y:10.3f}{s:10.4f}{k:5d}")

    sec = []
    for i, (n0, n1) in enumerate(zip(order, order[1:]), 1):
        x0, x1 = sizes[n0] / 1e9, sizes[n1] / 1e9
        y0, s0, _ = cells[n0]
        y1, s1, _ = cells[n1]
        sigma = math.hypot(s0, s1) / (x1 - x0)
        if sigma == 0:
            die(f"secant {n0} -> {n1} has sigma 0: identical values give the mean no weight")
        sec.append({"i": i, "n0": n0, "n1": n1, "x0": x0, "x1": x1, "s0": s0, "s1": s1,
                    "slope": (y1 - y0) / (x1 - x0), "sigma": sigma})

    print()
    print("adjacent secants; sigma comes from the two bounds named in the row")
    print(f"  {'id':4s}{'cell pair (ascending x)':34s}{'from_GB':>9s}{'to_GB':>9s}{'dx_GB':>8s}"
          f"{'slope_ms/GB':>13s}{'sigma':>8s}{'sig_from':>10s}{'sig_to':>8s}")
    for s in sec:
        print(f"  s{s['i']:<3d}{s['n0'] + ' -> ' + s['n1']:34s}{s['x0']:9.3f}{s['x1']:9.3f}"
              f"{s['x1'] - s['x0']:8.3f}{s['slope']:13.2f}{s['sigma']:8.2f}"
              f"{s['s0']:10.4f}{s['s1']:8.4f}")

    print()
    print("secants as published, each over its own interval and not to be averaged")
    for s in sec:
        print(f"  {s['slope']:6.2f} +/- {s['sigma']:.2f} ms/GB over {s['x0']:.3f} -> "
              f"{s['x1']:.3f} GB   ({s['n0']} -> {s['n1']})")

    print()
    print(f"neighbouring secants, 1 dof; they must agree within {AGREE_SIGMA:g} sigma "
          f"(chi2 <= {AGREE_SIGMA ** 2:.2f}) for a mean to be licensed")
    print(f"  {'pair':10s}{'difference':>11s}{'combined_sigma':>16s}{'z':>8s}{'chi2':>9s}   verdict")
    bad = []
    for p, q in zip(sec, sec[1:]):
        d = q["slope"] - p["slope"]
        cs = math.hypot(p["sigma"], q["sigma"])
        z = (d / cs) if cs else (0.0 if d == 0 else math.inf)
        ok = abs(z) <= AGREE_SIGMA
        if not ok:
            bad.append((p, q, z))
        print(f"  s{p['i']} vs s{q['i']:<4d}{d:11.2f}{cs:16.3f}{z:8.2f}{z * z:9.2f}   "
              f"{'agree' if ok else 'DISAGREE'}")

    print()
    if bad:
        print(f"MEAN REFUSED: {len(bad)} of {len(sec) - 1} neighbouring secant pairs differ by "
              f"more than {AGREE_SIGMA:g} sigma.")
        for p, q, z in bad:
            print(f"  s{p['i']} ({p['slope']:.2f} over {p['n0']} -> {p['n1']}) vs "
                  f"s{q['i']} ({q['slope']:.2f} over {q['n0']} -> {q['n1']}): {abs(z):.2f} sigma")
        print("  Rule 3, corollary: two probes that disagree by more than the noise floor are two")
        print("  observations, not one quantity. No weighted mean is computed or printed here.")
        print("  Publish the secants above, each over its own interval.")
        return EXIT_REFUSED

    w = [1.0 / s["sigma"] ** 2 for s in sec]
    mean = sum(wi * s["slope"] for wi, s in zip(w, sec)) / sum(w)
    smean = math.sqrt(1.0 / sum(w))
    print(f"inverse-variance weighted mean over {len(sec)} secants, neighbours agreeing within "
          f"{AGREE_SIGMA:g} sigma:")
    print(f"  {mean:.2f} +/- {smean:.2f} ms/GB over {sec[0]['x0']:.3f} -> {sec[-1]['x1']:.3f} GB")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
