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

## Tools

| Tool | Operations |
|---|---|
| `sympy_expression` | simplify, expand, factor, cancel, together, apart, evaluate, differentiate, integrate, limit, series, summation, product, laplace_transform, inverse_laplace_transform, fourier_transform, inverse_fourier_transform |
| `sympy_solve` | solve (equations, systems, inequalities), solveset, nsolve, dsolve |
| `sympy_matrix` | determinant, inverse, transpose, rank, rref, nullspace, eigenvalues, eigenvectors, multiply, linear_solve |
| `sympy_verify` | equivalent (two expressions), solution (values against equations) |

The JSON schemas live in `tosh_sympy/schema.py` and nowhere else. A result is one JSON object:

```json
{"success": true, "operation": "integrate", "exact": "sqrt(pi)", "latex": "\\sqrt{\\pi}",
 "numeric": "1.77245385090552", "warnings": []}
{"success": false, "operation": "factor", "error": {"code": "invalid_expression", "message": "..."}}
```

Error codes: `invalid_arguments`, `invalid_expression`, `unknown_function`, `input_too_large`,
`too_large`, `no_result`, `not_supported`, `math_error`, `timeout`, `memory_limit`,
`output_too_large`, `worker_crashed`, `runtime_unavailable`.

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
- is killed by the supervisor after `TOSH_SYMPY_TIMEOUT_MS` (default 15000) or above
  `TOSH_SYMPY_MEMORY_MB` (default 1024), and started again on the next call;
- exits after `TOSH_SYMPY_IDLE_SECONDS` (default 300) without use.

Inputs are capped at 4000 characters per expression and 64 KB per request, results at 6000
characters per field.

## Tests

```sh
./scripts/build-sympy.sh
vendor/tosh-sympy/python/bin/python3 -I helpers/tosh-sympy/tests/test_helper.py
TOSH_SYMPY_E2E_MODEL=~/models/Qwen3-4B-Q4_K_M.gguf ./scripts/test.sh --filter SymPyEngine
```
