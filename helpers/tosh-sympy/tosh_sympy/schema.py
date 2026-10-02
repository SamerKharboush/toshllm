# ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
# Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tool definitions. The schemas here are the only description of the API."""

_SYNTAX = (
    "Expressions are plain math text such as x**2*sin(x), (a + b)/c, sqrt(2), exp(-t), pi, E, I, oo. "
    "Use * for products and ** or ^ for powers. Decimals are read as exact fractions. "
    "Python code is not accepted."
)

_MATH = {"type": "string"}
_ASSUMPTIONS = {
    "type": "object",
    "description": "Optional facts about variables, e.g. {\"x\": [\"real\", \"positive\"]}. "
                   "Allowed: real, positive, negative, nonnegative, nonpositive, nonzero, integer, "
                   "rational, complex, even, odd, prime.",
    "additionalProperties": {"type": "array", "items": {"type": "string"}},
}
_PRECISION = {"type": "integer", "minimum": 1, "maximum": 1000,
              "description": "Significant digits for decimal values (default 15)."}
_MATRIX = {"type": "array", "items": {"type": "array", "items": _MATH}}

TOOLS = {
    "expression": {
        "description": (
            "Exact symbolic algebra and calculus on one expression: simplify, expand, factor, cancel, "
            "together, apart (partial fractions), evaluate (decimal value), differentiate, integrate, "
            "limit, series, summation, product, and Laplace and Fourier transforms with their inverses. "
            + _SYNTAX),
        "operations": [
            "simplify", "expand", "factor", "cancel", "together", "apart", "evaluate",
            "differentiate", "integrate", "limit", "series", "summation", "product",
            "laplace_transform", "inverse_laplace_transform",
            "fourier_transform", "inverse_fourier_transform",
        ],
        "properties": {
            "expression": {**_MATH, "description": "The expression to work on."},
            "variable": {**_MATH, "description": "Variable of differentiation, integration, limit, series, "
                                                 "sum or transform. Optional when there is only one."},
            "order": {"type": "integer", "description": "Derivative order (default 1) or number of series terms (default 6)."},
            "lower": {**_MATH, "description": "Lower bound of a definite integral, sum or product."},
            "upper": {**_MATH, "description": "Upper bound of a definite integral, sum or product."},
            "point": {**_MATH, "description": "Point of a limit or of a series expansion, e.g. 0 or oo."},
            "direction": {"type": "string", "enum": ["both", "+", "-"],
                          "description": "Side a limit is taken from (default both)."},
            "transform_variable": {**_MATH, "description": "Output variable of a transform (default s, t, k or x)."},
            "substitutions": {"type": "object", "additionalProperties": _MATH,
                              "description": "Values to substitute first, e.g. {\"x\": \"2\"}."},
            "assumptions": _ASSUMPTIONS,
            "precision": _PRECISION,
        },
        "required": ["operation", "expression"],
    },
    "solve": {
        "description": (
            "Solve equations exactly: solve (one equation, a system, or an inequality), solveset (the full "
            "solution set of one equation over the real or complex numbers), dsolve (an ordinary "
            "differential equation, written with y' and y'' or diff(y(x), x)), and nsolve (numerical root "
            "near an initial guess). Write each equation as \"left = right\". " + _SYNTAX),
        "operations": ["solve", "solveset", "nsolve", "dsolve"],
        "properties": {
            "equations": {"type": "array", "items": _MATH,
                          "description": "Equations or inequalities, e.g. [\"x**2 - 5*x + 6 = 0\"]."},
            "variables": {"type": "array", "items": _MATH,
                          "description": "Unknowns to solve for. Optional when every variable is an unknown."},
            "domain": {"type": "string", "enum": ["complex", "real"],
                       "description": "Domain for solveset (default complex)."},
            "function": {**_MATH, "description": "Name of the unknown function for dsolve (default y)."},
            "variable": {**_MATH, "description": "Independent variable for dsolve (default x)."},
            "initial_conditions": {"type": "object", "additionalProperties": _MATH,
                                   "description": "For dsolve, e.g. {\"y(0)\": \"1\", \"y'(0)\": \"0\"}."},
            "initial_guess": {"type": "array", "items": _MATH,
                              "description": "For nsolve: one starting value per variable."},
            "assumptions": _ASSUMPTIONS,
            "precision": _PRECISION,
        },
        "required": ["operation", "equations"],
    },
    "matrix": {
        "description": (
            "Exact linear algebra on a matrix given as a list of rows: determinant, inverse, transpose, "
            "rank, rref, nullspace, eigenvalues, eigenvectors, multiply (matrix times other) and "
            "linear_solve (solve matrix * x = other). Entries may be numbers or expressions. " + _SYNTAX),
        "operations": [
            "determinant", "inverse", "transpose", "rank", "rref", "nullspace",
            "eigenvalues", "eigenvectors", "multiply", "linear_solve",
        ],
        "properties": {
            "matrix": {**_MATRIX, "description": "Rows of the matrix, e.g. [[\"1\", \"2\"], [\"3\", \"4\"]]."},
            "other": {**_MATRIX, "description": "Second matrix for multiply, or the right-hand side column for linear_solve."},
            "assumptions": _ASSUMPTIONS,
            "precision": _PRECISION,
        },
        "required": ["operation", "matrix"],
    },
    "verify": {
        "description": (
            "Check mathematics before presenting it. equivalent: whether 'left' and 'right' are the same "
            "expression, returning their simplified difference when they are not. solution: whether the "
            "values in 'solution' satisfy every equation, returning the residual of each. For a "
            "differential equation set 'function' and give the candidate as {\"y\": \"...\"}. " + _SYNTAX),
        "operations": ["equivalent", "solution"],
        "properties": {
            "left": {**_MATH, "description": "First expression (equivalent)."},
            "right": {**_MATH, "description": "Second expression (equivalent)."},
            "equations": {"type": "array", "items": _MATH,
                          "description": "Equations or inequalities to check (solution)."},
            "solution": {"type": "object", "additionalProperties": _MATH,
                         "description": "Proposed values, e.g. {\"x\": \"2\"}."},
            "function": {**_MATH, "description": "Unknown function name when checking a differential equation."},
            "variable": {**_MATH, "description": "Independent variable of that function (default x)."},
            "substitutions": {"type": "object", "additionalProperties": _MATH,
                              "description": "Values to substitute into 'left' and 'right' first."},
            "assumptions": _ASSUMPTIONS,
            "precision": _PRECISION,
        },
        "required": ["operation"],
    },
}


def definitions():
    """The tools in MCP tools/list form."""
    listed = []
    for name, tool in TOOLS.items():
        properties = {"operation": {"type": "string", "enum": tool["operations"],
                                    "description": "What to do."}}
        properties.update(tool["properties"])
        listed.append({
            "name": name,
            "description": tool["description"],
            "inputSchema": {
                "type": "object",
                "properties": properties,
                "required": tool["required"],
                "additionalProperties": False,
            },
            "annotations": {"readOnlyHint": True, "openWorldHint": False},
        })
    return listed


def check(name, arguments):
    """Returns the operation, or raises ValueError naming what is wrong with the call."""
    tool = TOOLS.get(name)
    if tool is None:
        raise ValueError(f"unknown tool '{str(name)[:40]}'")
    if not isinstance(arguments, dict):
        raise ValueError("arguments must be an object")
    operation = arguments.get("operation")
    if operation not in tool["operations"]:
        raise ValueError("'operation' must be one of: " + ", ".join(tool["operations"]))
    unknown = [key for key in arguments if key != "operation" and key not in tool["properties"]]
    if unknown:
        raise ValueError(f"unknown argument '{str(unknown[0])[:40]}'; allowed: "
                         + ", ".join(tool["properties"]))
    return operation
