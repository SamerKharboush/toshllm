#!/usr/bin/env python3
"""A derived figure does not ship unless this script prints it and passes.

Residuals are judged against an externally measured noise floor, and the verdict
is on the whole fit, never on the quoted cell. Standard library only.

    ./tools/fitgate.py --noise-rel 0.0011 name:bytes:ms [...]
"""
import argparse, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--noise-rel", type=float, required=True,
                    help="external noise floor as a fraction of the measured value, e.g. 0.0011 for 0.11%%")
    ap.add_argument("--reject-at", type=float, default=3.0, help="worst residual, in multiples of the noise floor")
    ap.add_argument("--chi2-max", type=float, default=3.0)
    ap.add_argument("cells", nargs="+", help="name:bytes:y")
    a = ap.parse_args()

    pts = []
    for c in a.cells:
        parts = c.split(":")
        if len(parts) != 3:
            print(f"bad cell {c!r}; want name:bytes:y"); return 2
        pts.append((parts[0], float(parts[1]), float(parts[2])))
    n, p = len(pts), 2
    if n < p + 1:
        print(f"REJECT: n={n} with p={p} leaves no degrees of freedom"); return 1

    mx = sum(b for _, b, _ in pts) / n
    my = sum(y for _, _, y in pts) / n
    sxx = sum((b - mx) ** 2 for _, b, _ in pts)
    sxy = sum((b - mx) * (y - my) for _, b, y in pts)
    slope, intercept = sxy / sxx, my - sxy / sxx * mx
    dof = n - p

    print(f"n={n}  p={p}  dof={dof}")
    print(f"slope={slope:.6g}  intercept={intercept:.6g}")
    print(f"external noise floor: {a.noise_rel:.4%} relative")
    print()
    worst = chi2 = 0.0
    for name, b, y in pts:
        r = y - (intercept + slope * b)
        frac = abs(r) / y
        worst = max(worst, frac)
        chi2 += (r / (y * a.noise_rel)) ** 2
        lev = (b - mx) ** 2 / sxx
        print(f"  {name:16s} bytes={b:9.4f}  y={y:8.3f}  resid={r:+8.3f} ({frac / a.noise_rel:5.1f}x noise)  leverage={lev:.3f}")
    chi2 /= dof
    print()
    print(f"worst residual: {worst:.4%} = {worst / a.noise_rel:.1f}x the noise floor")
    print(f"reduced chi-squared: {chi2:.1f}")
    ok = worst / a.noise_rel <= a.reject_at and chi2 <= a.chi2_max
    print("VERDICT:", "PASS" if ok else f"REJECT ({a.reject_at:g}x noise, chi2_red<={a.chi2_max:g} required)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
