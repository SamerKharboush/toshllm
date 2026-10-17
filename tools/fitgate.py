#!/usr/bin/env python3
"""A derived figure does not ship unless this script prints it and passes.

Standard library only.

The noise floor is EXTERNAL and is passed in. It must come from repeated
measurement of the same cell. It must never be computed from the residuals:
with dof == 1 every studentized residual is exactly +-1, so an internal floor
makes reduced chi-squared identically 1 and the gate can never fail.

    ./tools/fitgate.py --noise-rel 0.001 name:bytes:ms [...]
"""
import argparse, math, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--noise-rel", type=float, required=True,
                    help="EXTERNAL noise floor, as a fraction of each measured value (0.001 = 0.1%%)")
    ap.add_argument("--reject-at", type=float, default=3.0)
    ap.add_argument("--chi2-max", type=float, default=3.0)
    ap.add_argument("--leverage-alarm", type=float, default=0.9)
    ap.add_argument("--loo-swing", type=float, default=0.20)
    ap.add_argument("cells", nargs="+", help="name:bytes:y")
    a = ap.parse_args()

    pts = []
    for c in a.cells:
        f = c.split(":")
        if len(f) != 3:
            print(f"bad cell {c!r}; want name:bytes:y"); return 2
        pts.append((f[0], float(f[1]), float(f[2])))
    n, p = len(pts), 2
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

    resid, h = [], []
    for _, b, y in pts:
        resid.append(y - (intercept + slope * b))
        h.append(1.0 / n + (b - mx) ** 2 / sxx)
    dof = n - p
    sigma = [y * a.noise_rel for _, _, y in pts]
    z = [r / s for r, s in zip(resid, sigma)]
    chi2 = sum(zi * zi for zi in z) / dof
    worst = max(abs(zi) for zi in z)
    ss_res = sum(r * r for r in resid)
    ss_tot = sum((y - my) ** 2 for _, _, y in pts)
    r2 = 1 - ss_res / ss_tot

    print(f"n={n}  p={p}  dof={dof}")
    print(f"slope={slope:.4f} ms/unit   intercept={intercept:.3f}")
    print(f"noise floor (external): {a.noise_rel:.4%} relative"
          f"  -> sigma per cell {[round(s,4) for s in sigma]}")
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
    return 0 if not problems else 1

if __name__ == "__main__":
    sys.exit(main())
