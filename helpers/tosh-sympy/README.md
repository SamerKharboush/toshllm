# tosh-sympy

Symbolic math tools for the engine, backed by [SymPy](https://www.sympy.org). It is an MCP
server over stdio, so `llama-server` lists its tools on `/tools` next to its own and any
OpenAI-compatible client of the server can call them.

```
llama-server --mcp-servers-json '{"mcpServers":{"sympy":{...}}}'
    └── tosh_sympy/server.py     supervisor, never imports SymPy (about 8 MB)
            └── tosh_sympy/worker.py     SymPy, started on the first call
```

`scripts/build-sympy.sh` builds the runtime in `vendor/tosh-sympy` from a pinned CPython,
SymPy and mpmath, and `make-app.sh` copies it to `Contents/Resources/tosh-sympy`. No Python
from the system is used, to build or to run. In the app it is off until **Symbolic math
(SymPy)** is switched on in the chat settings, under Agents.

The same runtime carries NumPy and SciPy for the [numerical tools](../tosh-scientific/README.md).
Those run as a second server, `server.py scientific`, with a worker of their own: this one
never loads either library.

## Tools

| Tool | Operations |
|---|---|
| `sympy_expression` | simplify, expand, factor, cancel, together, apart, evaluate, differentiate, integrate, limit, series, summation, product, laplace_transform, inverse_laplace_transform, fourier_transform, inverse_fourier_transform |
| `sympy_solve` | solve (equations, systems, inequalities), solveset, nsolve, dsolve |
| `sympy_matrix` | determinant, inverse, transpose, rank, rref, nullspace, eigenvalues, eigenvectors, multiply, linear_solve |
| `sympy_verify` | equivalent (two expressions), solution (values against equations) |

The JSON schemas live in `tosh_sympy/schema.py` and nowhere else. They are kept short on
purpose: every conversation that offers the tools carries them, about 1000 tokens in all. A
few arguments are accepted without being advertised (`assumptions`, `precision` and
`substitutions` on every tool, `transform_variable` on transforms).

A result is one JSON object:

```json
{"success": true, "operation": "integrate", "exact": "sqrt(pi)", "latex": "\\sqrt{\\pi}",
 "numeric": "1.77245385090552", "warnings": []}
{"success": false, "operation": "factor", "error": {"code": "invalid_expression", "message": "..."}}
```

Error codes: `invalid_arguments`, `invalid_expression`, `unknown_function`, `input_too_large`,
`too_large`, `no_result`, `not_supported`, `math_error`, `no_closed_form`, `timeout`,
`memory_limit`, `output_too_large`, `worker_crashed`, `runtime_unavailable`.

### When there is no exact answer

An exact result and an approximation are never mixed up. `exact` is `null` whenever the
value below it is not a closed form.

```json
{"success": true, "operation": "integrate", "exact": null,
 "unevaluated": "Integral(exp(sin(x)), (x, 0, 1))", "numeric": "1.63186960841805",
 "method": "numerical_integration", "error_estimate": "1.0e-51", "precision": 15,
 "timed_out_symbolic": false, "warnings": ["no closed form was obtained; ..."]}
{"success": false, "operation": "integrate", "exact": null, "timed_out": true,
 "unevaluated": "Integral(1/(x**3 + sin(x) + 1), x)",
 "error": {"code": "timeout", "message": "No closed form was obtained within the 15 s computation budget."}}
```

- A definite integral with finite numeric bounds and no free parameters falls back to
  numerical quadrature when SymPy leaves it open or runs out of time. The value is kept only
  if two different subdivisions of the interval agree, so a divergent or singular integral
  gets `no_closed_form`, not a number.
- An indefinite integral, an integral with a parameter or an infinite bound, a sum, a
  product, a limit or a transform SymPy cannot close returns `no_closed_form` with the
  `unevaluated` form.
- A request stopped by the time budget returns `timed_out: true`. For a series it also
  carries the expansion to the highest lower order that finished, under `partial`. For an
  integral it tries the numerical fallback, and one exact retry with the trigonometric
  functions rewritten as exponentials.
- `nsolve` never invents a starting point: without `initial_guess` it says so.
- `e` is Euler's number, like `E`, unless the request names it as a variable (`variable`,
  `variables`, or a key of `assumptions`, `substitutions` or `solution`).

## What the model can and cannot send

The model sends math, never code. `tosh_sympy/mathlang.py` tokenizes and parses each
expression itself and builds SymPy objects from a fixed table of functions and constants.
No text from the model reaches `sympify`, `parse_expr`, `eval` or `exec`, and `nsolve` runs on closures
instead of `lambdify`. SymPy does compile code of its own while it works (polynomial kernels,
its integral tables); that text is SymPy's, and a variable name can only be letters, digits
and underscores, so it stays inert wherever it is printed.

On top of that the worker:

- runs under a macOS sandbox profile with no network, no file writes, no new processes and no
  reads under `/Users` or `/Volumes` outside the runtime;
- has a Python audit hook that refuses the same things;
- is killed by the supervisor after `TOSH_SYMPY_TIMEOUT_MS` (default 15000, at most 20000) or
  above `TOSH_SYMPY_MEMORY_MB` (default 1024). After a timeout a fresh worker gets 5 s to
  report what it still can about the request;
- runs with a fixed hash seed. SymPy's heuristics walk sets, and with Python's random string
  hashing the same integral took 0.6 s in one process and never finished in the next;
- exits after `TOSH_SYMPY_IDLE_SECONDS` (default 300) without use.

Inputs are capped at 4000 characters per expression and 64 KB per request, results at 6000
characters per field.

## Tests

```sh
./scripts/build-sympy.sh
vendor/tosh-sympy/python/bin/python3 -I helpers/tosh-sympy/tests/test_helper.py
TOSH_SYMPY_E2E_MODEL=~/models/Qwen3-4B-Q4_K_M.gguf ./scripts/test.sh --filter SymPyEngine
```
