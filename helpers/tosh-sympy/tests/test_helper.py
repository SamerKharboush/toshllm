# ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
# Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the SymPy helper, driven over its MCP stdio protocol.

Run with the bundled interpreter, which has no unittest:
    vendor/tosh-sympy/python/bin/python3 -I helpers/tosh-sympy/tests/test_helper.py [runtime dir]
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
RUNTIME = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "vendor", "tosh-sympy")
PYTHON = os.path.join(RUNTIME, "python", "bin", "python3")


class Helper:
    def __init__(self, **environment):
        self.process = subprocess.Popen(
            [PYTHON, "-I", "-B", os.path.join(RUNTIME, "tosh_sympy", "server.py")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
            env={key: str(value) for key, value in environment.items()})
        self.next_id = 0
        self.rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}})

    def rpc(self, method, params=None):
        self.next_id += 1
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        reply = json.loads(self.process.stdout.readline())
        assert reply["id"] == self.next_id, reply
        return reply

    def call(self, tool, **arguments):
        result = self.rpc("tools/call", {"name": tool, "arguments": arguments})["result"]
        reply = json.loads(result["content"][0]["text"])
        assert result["isError"] == (not reply["success"]), result
        return reply

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)


def expression(helper, operation, text, **arguments):
    return helper.call("expression", operation=operation, expression=text, **arguments)


def error_code(reply):
    assert reply["success"] is False, reply
    assert set(reply) == {"success", "operation", "error"}, reply
    assert set(reply["error"]) == {"code", "message"}, reply
    return reply["error"]["code"]


def test_simplify(h):
    assert expression(h, "simplify", "(x**2 - 1)/(x - 1)")["exact"] == "x + 1"


def test_factor(h):
    reply = expression(h, "factor", "x**2 - 5*x + 6")
    assert reply["exact"] == "(x - 3)*(x - 2)", reply
    assert reply["latex"] and reply["warnings"] == [] and reply["operation"] == "factor"


def test_expand_cancel_apart_together(h):
    assert expression(h, "expand", "(x + 1)**2")["exact"] == "x**2 + 2*x + 1"
    assert expression(h, "cancel", "(x**2 - 1)/(x - 1)")["exact"] == "x + 1"
    assert expression(h, "apart", "1/(x**2 - 1)")["exact"] == "-1/(2*(x + 1)) + 1/(2*(x - 1))"
    assert expression(h, "together", "1/x + 1/y")["exact"] == "(x + y)/(x*y)"


def test_solve(h):
    reply = h.call("solve", operation="solve", equations=["x**2 - 5*x + 6 = 0"])
    assert reply["solutions"] == [{"x": "2"}, {"x": "3"}], reply


def test_solve_exact_roots(h):
    reply = h.call("solve", operation="solve", equations=["x**2 - 2 = 0"])
    assert reply["solutions"] == [{"x": "-sqrt(2)"}, {"x": "sqrt(2)"}], reply
    assert reply["numeric"][1]["x"].startswith("1.41421356"), reply


def test_solve_system(h):
    reply = h.call("solve", operation="solve", equations=["x + y = 3", "x - y = 1"])
    assert reply["solutions"] == [{"x": "2", "y": "1"}], reply


def test_solve_inequality(h):
    reply = h.call("solve", operation="solve", equations=["x**2 < 4"])
    assert reply["set"] == "Interval.open(-2, 2)", reply


def test_solveset(h):
    reply = h.call("solve", operation="solveset", equations=["x**2 + 1 = 0"], domain="real")
    assert reply["exact"] == "EmptySet", reply
    reply = h.call("solve", operation="solveset", equations=["x**2 + 1 = 0"])
    assert reply["solutions"] == [{"x": "-I"}, {"x": "I"}], reply


def test_derivative(h):
    assert expression(h, "differentiate", "x**2*sin(x)")["exact"] == "x**2*cos(x) + 2*x*sin(x)"
    assert expression(h, "differentiate", "x**5", order=2)["exact"] == "20*x**3"


def test_integral(h):
    reply = expression(h, "integrate", "x**2*sin(x)", variable="x")
    assert reply["exact"] == "-x**2*cos(x) + 2*x*sin(x) + 2*cos(x)", reply
    reply = expression(h, "integrate", "exp(-x**2)", lower="-oo", upper="oo")
    assert reply["exact"] == "sqrt(pi)" and reply["numeric"].startswith("1.7724538509"), reply


def test_limit(h):
    assert expression(h, "limit", "sin(x)/x", point="0")["exact"] == "1"
    assert expression(h, "limit", "(1 + 1/n)**n", point="oo")["exact"] == "E"
    assert expression(h, "limit", "1/x", point=0, direction="+")["exact"] == "oo"


def test_series(h):
    reply = expression(h, "series", "cos(x)", order=6)
    assert reply["exact"] == "1 - x**2/2 + x**4/24 + O(x**6)", reply


def test_sum_and_product(h):
    reply = expression(h, "summation", "1/n**2", variable="n", lower="1", upper="oo")
    assert reply["exact"] == "pi**2/6", reply
    reply = expression(h, "product", "k", variable="k", lower="1", upper="5")
    assert reply["exact"] == "120", reply


def test_matrix_determinant_and_inverse(h):
    matrix = [["1", "2"], ["3", "4"]]
    assert h.call("matrix", operation="determinant", matrix=matrix)["exact"] == "-2"
    assert h.call("matrix", operation="inverse", matrix=matrix)["matrix"] == [["-2", "1"], ["3/2", "-1/2"]]
    assert error_code(h.call("matrix", operation="inverse", matrix=[[1, 2], [2, 4]])) == "no_result"


def test_matrix_rank_and_linear_system(h):
    assert h.call("matrix", operation="rank", matrix=[[1, 2], [2, 4]])["exact"] == "1"
    reply = h.call("matrix", operation="linear_solve", matrix=[[1, 1], [1, -1]], other=[[3], [1]])
    assert reply["solution"] == ["2", "1"], reply
    reply = h.call("matrix", operation="multiply", matrix=[[1, 2], [3, 4]], other=[[0, 1], [1, 0]])
    assert reply["matrix"] == [["2", "1"], ["4", "3"]], reply


def test_eigenvalues(h):
    reply = h.call("matrix", operation="eigenvalues", matrix=[[2, 1], [1, 2]])
    assert [e["value"] for e in reply["eigenvalues"]] == ["1", "3"], reply
    reply = h.call("matrix", operation="eigenvectors", matrix=[[2, 1], [1, 2]])
    assert reply["eigenvectors"][1] == {"eigenvalue": "3", "multiplicity": 1, "vectors": [["1", "1"]]}, reply


def test_ode(h):
    reply = h.call("solve", operation="dsolve", equations=["y' = y"])
    assert reply["exact"] == "y(x) = C1*exp(x)", reply
    reply = h.call("solve", operation="dsolve", equations=["y'' + y = 0"],
                   initial_conditions={"y(0)": "1", "y'(0)": "0"})
    assert reply["exact"] == "y(x) = cos(x)", reply
    reply = h.call("solve", operation="dsolve", equations=["diff(f(t), t) = -2*f(t)"],
                   function="f", variable="t")
    assert reply["exact"] == "f(t) = C1*exp(-2*t)", reply


def test_laplace(h):
    assert expression(h, "laplace_transform", "exp(-a*t)")["exact"] == "1/(a + s)"
    assert expression(h, "inverse_laplace_transform", "1/(s**2 + 1)")["exact"] == "sin(t)*Heaviside(t)"


def test_fourier(h):
    assert expression(h, "fourier_transform", "exp(-x**2)")["exact"] == "sqrt(pi)*exp(-pi**2*k**2)"
    reply = expression(h, "inverse_fourier_transform", "sqrt(pi)*exp(-pi**2*k**2)")
    assert reply["exact"] == "exp(-x**2)", reply


def test_complex_arithmetic(h):
    assert expression(h, "simplify", "(1 + 2*I)*(3 - I)")["exact"] == "5 + 5*I"
    assert expression(h, "simplify", "exp(I*pi)")["exact"] == "-1"


def test_numeric_precision(h):
    reply = expression(h, "evaluate", "pi", precision=50)
    assert reply["numeric"] == "3.1415926535897932384626433832795028841971693993751", reply
    reply = h.call("solve", operation="nsolve", equations=["cos(x) = x"], initial_guess=["1"], precision=20)
    assert reply["numeric"][0]["x"].startswith("0.7390851332151606"), reply


def test_equivalent(h):
    reply = h.call("verify", operation="equivalent", left="(x + 1)**2", right="x**2 + 2*x + 1")
    assert reply["equivalent"] is True and reply["difference"] == "0", reply
    reply = h.call("verify", operation="equivalent", left="sin(x)**2 + cos(x)**2", right="1")
    assert reply["equivalent"] is True, reply


def test_not_equivalent(h):
    reply = h.call("verify", operation="equivalent", left="(x + 1)**2", right="x**2 + 2*x")
    assert reply["success"] is True and reply["equivalent"] is False and reply["difference"] == "1", reply


def test_verify_solution(h):
    equations = ["x**2 - 5*x + 6 = 0"]
    reply = h.call("verify", operation="solution", equations=equations, solution={"x": "2"})
    assert reply["satisfied"] is True and reply["checks"][0]["residual"] == "0", reply
    reply = h.call("verify", operation="solution", equations=equations, solution={"x": "4"})
    assert reply["satisfied"] is False and reply["checks"][0]["residual"] == "2", reply
    reply = h.call("verify", operation="solution", equations=["y'' + y = 0"], function="y",
                   solution={"y": "exp(x)"})
    assert reply["satisfied"] is False and reply["checks"][0]["residual"] == "2*exp(x)", reply


def test_assumptions(h):
    assert expression(h, "simplify", "sqrt(x**2)")["exact"] == "sqrt(x**2)"
    assert expression(h, "simplify", "sqrt(x**2)", assumptions={"x": ["positive"]})["exact"] == "x"
    assert error_code(expression(h, "simplify", "x", assumptions={"x": ["evil"]})) == "invalid_arguments"


def test_invalid_expression(h):
    for text in ("x +* 2", "(x + 1", "", "sin", "2 +", "x $ y", "foo(x)"):
        assert error_code(expression(h, "simplify", text)) in ("invalid_expression", "unknown_function"), text
    assert error_code(h.call("expression", operation="nope", expression="x")) == "invalid_arguments"
    assert error_code(h.call("expression", operation="simplify")) == "invalid_arguments"
    assert error_code(h.call("expression", operation="simplify", expression="x", extra=1)) == "invalid_arguments"
    assert error_code(h.call("nothing", operation="simplify")) == "invalid_arguments"


def test_code_injection(h):
    marker = os.path.join(os.environ.get("TMPDIR", "/tmp"), "tosh-sympy-injection-marker")
    attempts = [
        "__import__('os').system('touch %s')" % marker,
        "__import__(\"os\").system(\"touch %s\")" % marker,
        "exec('import os')", "eval('1+1')", "open('/etc/passwd').read()",
        "x.__class__.__mro__", "().__class__.__bases__[0].__subclasses__()",
        "lambda: 1", "[x for x in (1,2)]", "import os", "x; y", "getattr(x, 'y')",
        "globals()", "compile('1','a','eval')", "breakpoint()", "__builtins__",
        "sympify('1')", "S('1')", "Symbol('x')", "parse_expr('1')", "lambdify(x, x)",
        "f\"{x}\"", "x if x else y", "x := 2", "print(1)", "os.system", "\\x41",
    ]
    for text in attempts:
        code = error_code(expression(h, "simplify", text))
        assert code in ("invalid_expression", "unknown_function"), (text, code)
        for where in ("left", "right"):
            assert h.call("verify", operation="equivalent", **{"left": "x", "right": "x", where: text})["success"] is False
        assert h.call("solve", operation="solve", equations=[text])["success"] is False
        assert h.call("matrix", operation="determinant", matrix=[[text]])["success"] is False
    assert error_code(h.call("solve", operation="dsolve", equations=["y' = y"], function="__import__")) == "invalid_expression"
    assert error_code(h.call("solve", operation="solve", equations=["x = 1"], variables=["x); import os; ("])) == "invalid_expression"
    assert not os.path.exists(marker)


def test_size_limits(h):
    assert error_code(expression(h, "simplify", "x + " * 1500 + "x")) == "input_too_large"
    assert error_code(expression(h, "simplify", "(" * 200 + "x" + ")" * 200)) == "input_too_large"
    assert error_code(expression(h, "simplify", "9**9**9")) == "too_large"
    assert error_code(expression(h, "simplify", "factorial(10**6)")) == "too_large"
    assert error_code(expression(h, "simplify", "1" * 400)) == "too_large"
    assert error_code(h.call("matrix", operation="rank", matrix=[["1"] * 17] * 17)) == "input_too_large"
    assert error_code(expression(h, "evaluate", "pi", precision=100000)) == "invalid_arguments"
    assert error_code(expression(h, "simplify", "x", assumptions={"x" * 70000: ["real"]})) == "input_too_large"


def test_output_is_bounded(h):
    reply = expression(h, "expand", "(x + y + z + w)**40")
    assert reply["success"] and reply["truncated"] is True, reply
    assert len(reply["exact"]) == 6000 and "latex" not in reply, len(reply["exact"])
    assert len(json.dumps(reply)) < 8000


def test_timeout_and_recovery(_):
    helper = Helper(TOSH_SYMPY_TIMEOUT_MS=1500)
    try:
        started = time.monotonic()
        reply = expression(helper, "expand", "(a + b + c + d + f + g)**90")
        elapsed = time.monotonic() - started
        assert error_code(reply) == "timeout", reply
        assert elapsed < 4, elapsed
        assert expression(helper, "factor", "x**2 - 1")["exact"] == "(x - 1)*(x + 1)"
    finally:
        helper.close()


def test_memory_limit(_):
    helper = Helper(TOSH_SYMPY_MEMORY_MB=200, TOSH_SYMPY_TIMEOUT_MS=25000)
    try:
        assert error_code(expression(helper, "expand", "(a + b + c + d + f + g)**90")) == "memory_limit"
        assert expression(helper, "factor", "x**2 - 1")["success"] is True
    finally:
        helper.close()


def test_idle_worker_is_released(_):
    helper = Helper(TOSH_SYMPY_IDLE_SECONDS=1)
    try:
        expression(helper, "factor", "x**2 - 1")
        children = lambda: subprocess.run(["/usr/bin/pgrep", "-P", str(helper.process.pid)],
                                          capture_output=True, text=True).stdout.split()
        assert len(children()) == 1
        time.sleep(7)
        assert children() == []
        assert expression(helper, "factor", "x**2 - 1")["success"] is True
    finally:
        helper.close()


def test_worker_is_confined(_):
    probe = r'''
import os, sys
sys.path.insert(0, sys.argv[1])
from tosh_sympy import worker
import sympy
print(worker._sandbox())
sys.addaudithook(worker._audit)
def attempt(action):
    try:
        action()
        print("allowed")
    except Exception as error:
        print("denied")
attempt(lambda: open(sys.argv[2], "w"))
attempt(lambda: os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT))
attempt(lambda: __import__("subprocess").run(["/usr/bin/true"]))
attempt(lambda: os.fork())
attempt(lambda: __import__("socket").create_connection(("127.0.0.1", 9), 1))
attempt(lambda: os.listdir(os.path.expanduser("~")))
attempt(lambda: sympy.integrate(sympy.Symbol("x") ** 2))
'''
    marker = os.path.join(os.environ.get("TMPDIR", "/tmp"), "tosh-sympy-write-marker")
    lines = subprocess.run([PYTHON, "-I", "-B", "-c", probe, RUNTIME, marker],
                           capture_output=True, text=True).stdout.split()
    home_is_inside_runtime = os.path.expanduser("~").startswith(RUNTIME)
    expected = ["True"] + ["denied"] * 5 + ["allowed" if home_is_inside_runtime else "denied", "allowed"]
    assert lines == expected, lines
    assert not os.path.exists(marker)


def test_protocol(h):
    tools = h.rpc("tools/list")["result"]["tools"]
    assert [t["name"] for t in tools] == ["expression", "solve", "matrix", "verify"]
    for tool in tools:
        schema = tool["inputSchema"]
        assert schema["additionalProperties"] is False and "operation" in schema["required"]
        assert schema["properties"]["operation"]["enum"]
        assert tool["annotations"]["readOnlyHint"] is True
    assert "error" in h.rpc("resources/list")
    assert h.rpc("ping")["result"] == {}


def measure():
    started = time.monotonic()
    helper = Helper()
    ready = time.monotonic() - started
    started = time.monotonic()
    expression(helper, "factor", "x**2 - 5*x + 6")
    first = time.monotonic() - started
    warm = []
    for _ in range(20):
        started = time.monotonic()
        expression(helper, "factor", "x**2 - 5*x + 6")
        warm.append(time.monotonic() - started)
    helper.close()
    warm.sort()
    print(f"supervisor start {ready * 1000:.0f} ms, first call {first * 1000:.0f} ms, "
          f"warm call median {warm[len(warm) // 2] * 1000:.1f} ms")


def main():
    tests = [(name, function) for name, function in globals().items() if name.startswith("test_")]
    helper = Helper()
    failed = 0
    for name, function in tests:
        try:
            function(helper)
            print(f"ok    {name}")
        except Exception as error:
            failed += 1
            print(f"FAIL  {name}: {type(error).__name__}: {str(error)[:500]}")
            if not helper.process.poll() is None:
                helper = Helper()
    helper.close()
    measure()
    print(f"{len(tests) - failed} of {len(tests)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
