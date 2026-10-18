#!/usr/bin/env python3
"""A derived figure does not ship unless this script prints it and passes.

Standard library only.

The calibration CSV is versioned: its first line is `# schema_version=1`. A file with
no version line, or with a version this gate does not know, is refused rather than
parsed, so a format change cannot be read as a measurement change.

Below MIN_CELLS cells the gate reports insufficiency and exits without fitting: with
p = 2 parameters, too few cells means one cell owns the leverage and the chord
describes its own geometry.

The noise floor is EXTERNAL. It comes from repeated measurement of the same cell,
either as a uniform relative fraction (--noise-rel) or, preferably, from the raw
per-invocation calibration CSV (--calib), which gives each cell its own measured
sigma. It must never be computed from the residuals: with dof == 1 every
studentized residual is exactly +-1, so an internal floor makes reduced
chi-squared identically 1 and the gate can never fail.

    ./tools/fitgate.py --calib tools/calibrate/results/calibration-3cell-2026-10-18.csv \
        --calib-test tg128 name:bytes:ms [...]

    ./tools/fitgate.py --noise-rel 0.001 name:bytes:ms [...]      # uniform fallback

Sigma drift is checked by pointing --drift-calib at a freshly measured calibration:

    ./tools/fitgate.py --calib recorded.csv --drift-calib fresh.csv name:bytes:ms [...]

y is milliseconds per token. sigma comes back in tokens per second, so it is
propagated: y = 1000/t gives sigma_y = (1000/t^2) * sigma_t = (y^2/1000) * sigma_t.
"""
import argparse, csv, math, statistics, sys

SCHEMA_VERSION = 1      # first line of the calibration CSV; any other version is refused
MIN_CELLS = 5           # below this, p = 2 cannot be spread: one cell owns the leverage
DRIFT_MAX = 2.0         # fresh/recorded sigma ratio that counts as a measurement change
EXIT_INSUFFICIENT = 3   # distinct from 1 (fit rejected) and 2 (usage), so CI can tell them apart


def load_calib(path):
    """Rows of a calibration CSV whose first line declares a version we know."""
    lines = open(path).read().splitlines()
    head = lines[0].strip() if lines else ""
    if not head.startswith("# schema_version="):
        raise SystemExit(f"{path}: no '# schema_version=' line; "
                         f"refusing to read an unversioned calibration")
    ver = head.split("=", 1)[1].strip()
    if ver != str(SCHEMA_VERSION):
        raise SystemExit(f"{path}: schema version {ver!r}, gate knows {SCHEMA_VERSION}; refusing")
    return list(csv.DictReader(lines[1:]))


def sigma_from_calib(path, test, names):
    """Per-cell sigma in t/s, straight from the raw per-invocation rows."""
    rows = load_calib(path)
    if not rows:
        raise SystemExit(f"{path}: empty")
    if test not in rows[0]:
        raise SystemExit(f"{path}: no column {test!r}; has {sorted(rows[0])}")

    by_cell = {}
    for r in rows:
        raw = (r.get(test) or "").strip()
        if raw:
            by_cell.setdefault(r["cell"], []).append(float(raw))

    sig, ns = {}, {}
    for cell, vals in by_cell.items():
        if len(vals) < 2:
            continue
        sig[cell] = statistics.stdev(vals)
        ns[cell] = len(vals)

    missing = [n for n in names if n not in sig]
    return sig, ns, missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--noise-rel", type=float,
                    help="EXTERNAL uniform noise floor as a fraction of each measured value")
    ap.add_argument("--calib", help="raw per-invocation calibration CSV; sigma is measured from it")
    ap.add_argument("--calib-test", default="tg128",
                    help="column of the calibration CSV to take sigma from (default tg128)")
    ap.add_argument("--min-cells", type=int, default=MIN_CELLS,
                    help=f"cells needed before a fit is attempted (default {MIN_CELLS})")
    ap.add_argument("--drift-calib",
                    help="a freshly measured calibration CSV; its per-cell sigma is compared "
                         "with --calib's as drift")
    ap.add_argument("--drift-max", type=float, default=DRIFT_MAX,
                    help=f"sigma drift ratio, either direction, that alarms (default {DRIFT_MAX:g})")
    ap.add_argument("--reject-at", type=float, default=3.0)
    ap.add_argument("--chi2-max", type=float, default=3.0)
    ap.add_argument("--leverage-alarm", type=float, default=0.9)
    ap.add_argument("--loo-swing", type=float, default=0.20)
    ap.add_argument("cells", nargs="+", help="name:bytes:y   (y in ms per token)")
    a = ap.parse_args()

    if (a.calib is None) == (a.noise_rel is None):
        print("REJECT: give exactly one noise floor, --calib or --noise-rel"); return 2

    pts = []
    for c in a.cells:
        f = c.split(":")
        if len(f) != 3:
            print(f"bad cell {c!r}; want name:bytes:y"); return 2
        pts.append((f[0], float(f[1]), float(f[2])))
    n, p = len(pts), 2
    names = [nm for nm, _, _ in pts]

    if a.calib is not None:
        sig, ns, missing = sigma_from_calib(a.calib, a.calib_test, names)
        if missing:
            print(f"REJECT: no calibration sigma for {missing}; "
                  f"refusing to fall back to a modelled floor")
            return 1
        print(f"noise floor (measured): {a.calib}")
        for nm in names:
            print(f"  {nm:14s} sigma {sig[nm]:.4f} t/s  from n={ns[nm]} invocations of {a.calib_test}")
        print()
    else:
        sig = None
        print(f"noise floor (external, uniform): {a.noise_rel:.4%} relative")

    drift_alarm = False
    if a.drift_calib is not None:
        if sig is None:
            print("REJECT: --drift-calib compares against the recorded sigma, so it needs --calib")
            return 2
        dsig, _, dmissing = sigma_from_calib(a.drift_calib, a.calib_test, names)
        if dmissing:
            raise SystemExit(f"{a.drift_calib}: no fresh sigma for {dmissing}; "
                             f"refusing to compare a partial set")
        print(f"sigma drift (fresh {a.drift_calib} vs recorded {a.calib}, "
              f"alarm past {a.drift_max:g}x either way):")
        for nm in names:
            ratio = dsig[nm] / sig[nm]
            bad = ratio > a.drift_max or ratio < 1.0 / a.drift_max
            drift_alarm = drift_alarm or bad
            print(f"  {nm:14s} recorded {sig[nm]:.4f}  fresh {dsig[nm]:.4f} t/s  "
                  f"ratio {ratio:.2f}x{'   *** DRIFT ***' if bad else ''}")
        print()

    if n < a.min_cells:
        print(f"cells = {n}   minimum = {a.min_cells}   (p = {p})")
        print(f"INSUFFICIENT: {n} cells cannot support a leverage analysis, so no slope is "
              f"computed and nothing here is publishable. Measure more cells.")
        return EXIT_INSUFFICIENT

    if n - p < 1:
        print(f"REJECT: n={n} p={p} leaves dof={n-p}; dof must be >= 1"); return 1

    mx = sum(b for _, b, _ in pts) / n
    my = sum(y for _, _, y in pts) / n
    sxx = sum((b - mx) ** 2 for _, b, _ in pts)
    sxy = sum((b - mx) * (y - my) for _, b, y in pts)
    slope = sxy / sxx
    intercept = my - slope * mx

    def fit(xs, ys):
        k = len(xs); ax = sum(xs)/k; ay = sum(ys)/k
        sxx = sum((x-ax)**2 for x in xs)
        return sum((x-ax)*(y-ay) for x, y in zip(xs, ys)) / sxx

    resid, h, sigma = [], [], []
    for nm, b, y in pts:
        resid.append(y - (intercept + slope * b))
        h.append(1.0 / n + (b - mx) ** 2 / sxx)
        if sig is None:
            sigma.append(y * a.noise_rel)
        else:
            # y = 1000/t  =>  sigma_y = (1000/t^2) * sigma_t = (y^2/1000) * sigma_t
            sigma.append((y * y / 1000.0) * sig[nm])

    dof = n - p
    z = [r / s for r, s in zip(resid, sigma)]
    chi2 = sum(zi * zi for zi in z) / dof
    worst = max(abs(zi) for zi in z)
    ss_res = sum(r * r for r in resid)
    ss_tot = sum((y - my) ** 2 for _, _, y in pts)
    r2 = 1 - ss_res / ss_tot

    print(f"n={n}  p={p}  dof={dof}")
    print(f"slope={slope * 1e9:.4f} ms/GB   (= {1000.0 / (slope * 1e9):.1f} GB/s if read as a rate)"
          f"   intercept={intercept:.3f} ms")
    print(f"sigma per cell (ms): {[round(s, 3) for s in sigma]}")
    print()
    print(f"{'cell':18s}{'x':>10s}{'y':>10s}{'resid':>10s}{'z':>9s}{'leverage':>10s}{'cookD':>9s}")
    any_alarm = False
    for (nm, b, y), r, hi, zi in zip(pts, resid, h, z):
        cook = (zi * zi / p) * (hi / (1 - hi))
        if hi > a.leverage_alarm:
            any_alarm = True
        print(f"{nm:18s}{b:10.4f}{y:10.3f}{r:+10.3f}{zi:9.2f}{hi:10.3f}{cook:9.2f}")
    print()
    sh = sum(h)
    print(f"sum of leverage = {sh:.6f}  (must equal p = {p})  "
          f"{'OK' if abs(sh - p) < 1e-9 else '*** ARITHMETIC ERROR ***'}")
    loo = []
    for i in range(n):
        xs = [b for j, (_, b, _) in enumerate(pts) if j != i]
        ys = [y for j, (_, _, y) in enumerate(pts) if j != i]
        loo.append(fit(xs, ys))
    swing = max(abs(s - slope) / abs(slope) for s in loo)
    print(f"leave-one-out slope swing (max) = {swing:.1%}   "
          f"{'*** DOMINATED ***' if swing > a.loo_swing else 'ok'}")
    print(f"R^2 = {r2:.4f}   (printed for context only; never a pass criterion)")
    print(f"worst |z| = {worst:.1f}x the noise floor")
    print(f"reduced chi-squared = {chi2:.1f}")
    print()
    problems = []
    if abs(sh - p) >= 1e-9: problems.append("leverage sum != p")
    if worst > a.reject_at: problems.append(f"worst |z| {worst:.1f} > {a.reject_at:g}")
    if chi2 > a.chi2_max: problems.append(f"chi2_red {chi2:.1f} > {a.chi2_max:g}")
    if any_alarm: problems.append(f"leverage > {a.leverage_alarm:g}")
    if swing > a.loo_swing: problems.append(f"LOO swing {swing:.1%} > {a.loo_swing:.0%}")
    print("VERDICT:", "PASS" if not problems else "REJECT (" + "; ".join(problems) + ")")
    if drift_alarm:
        print(f"DRIFT ALARM: a fresh sigma is more than {a.drift_max:g}x from the recorded one; "
              f"the denominator is stale, whatever the verdict above says")
    return 0 if (not problems and not drift_alarm) else 1


if __name__ == "__main__":
    sys.exit(main())
