#!/usr/bin/env python3
"""A check that has never failed is not evidence.

This project has produced three checks that could not fail: a sigma array printed
without cell names, which put one cell's noise on another and reached a published
number; an AVX2 grep that passes a 192-byte shell script; and a metal-file count
whose fatal error was redirected to /dev/null, counted as zero, and reported as a
measurement.

So a check runs against an input known to be bad first. If the bad input does not
trip it, no verdict is issued for the subject -- the check is broken, and a result
from a broken check is worse than no result.

    assertcheck.py --check 'grep -c needle {path}' \
                   --known-bad /tmp/has-needle --subject /tmp/no-needle

Exits 0 with a verdict only when the known-bad input trips the check.
Exits 3 when the check is broken.  Exits 4 when it fails on the subject.
"""
import argparse
import subprocess
import sys


def run(cmd):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def tripped(out):
    """A check 'trips' when it reports something other than zero or nothing."""
    o = out.strip()
    return bool(o) and o != "0"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", required=True, help="shell command, {path} substituted")
    ap.add_argument("--known-bad", required=True, help="input the check MUST flag")
    ap.add_argument("--subject", required=True, help="input under test")
    ap.add_argument("--describe", default="subject")
    a = ap.parse_args()

    bad_rc, bad_out, bad_err = run(a.check.replace("{path}", a.known_bad))
    if bad_rc != 0 or not tripped(bad_out):
        print(f"REFUSED: the check did not trip on the known-bad input.\n"
              f"  input:  {a.known_bad}\n"
              f"  rc:     {bad_rc}\n"
              f"  output: {bad_out!r}\n"
              f"  stderr: {bad_err!r}\n"
              f"  A check that cannot fail proves nothing. No verdict on the subject.",
              file=sys.stderr)
        return 3

    sub_rc, sub_out, sub_err = run(a.check.replace("{path}", a.subject))
    if sub_rc != 0:
        print(f"REFUSED: the check failed on the subject.\n"
              f"  rc: {sub_rc}  stderr: {sub_err!r}", file=sys.stderr)
        return 4

    # Each value is printed from the run that produced it. An earlier version of this
    # file printed the subject's value on the known-bad line, which is the same defect
    # it exists to catch.
    print(f"known-bad  {a.known_bad} -> {bad_out}")
    print(f"subject    {a.subject} -> {sub_out or '0'}")
    print(f"VERDICT: {a.describe} = {sub_out or '0'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
