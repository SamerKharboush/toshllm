# ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
# Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""The mathematical operations behind the tools. Every input goes through mathlang."""

import mpmath
import sympy as sp
from sympy.printing.str import StrPrinter

from .mathlang import Context, MathError, check_identifier, parse_expression, parse_relation

MAX_FIELD_CHARS = 6000
MAX_ITEMS = 64
MAX_MATRIX_SIDE = 16
MAX_EQUATIONS = 16
MAX_PRECISION = 1000
DEFAULT_PRECISION = 15


class _Printer(StrPrinter):
    # "a = b" reads back through mathlang, "Eq(a, b)" does not
    def _print_Equality(self, expr):
        return f"{self._print(expr.lhs)} = {self._print(expr.rhs)}"


_printer = _Printer()


class Reply:
    def __init__(self, operation):
        self.fields = {"success": True, "operation": operation}
        self.warnings = []

    def text(self, value):
        text = value if isinstance(value, str) else _printer.doprint(value)
        if len(text) > MAX_FIELD_CHARS:
            self.fields["truncated"] = True
            if "result truncated" not in " ".join(self.warnings):
                self.warnings.append(f"result truncated to {MAX_FIELD_CHARS} characters per field")
            return text[:MAX_FIELD_CHARS]
        return text

    def items(self, values):
        values = list(values)
        if len(values) > MAX_ITEMS:
            self.fields["truncated"] = True
            self.warnings.append(f"only the first {MAX_ITEMS} of {len(values)} results are listed")
        return values[:MAX_ITEMS]

    def value(self, value, precision, numeric=True):
        """The main result: exact text, LaTeX, and a decimal value when it is a number."""
        self.fields["exact"] = self.text(value)
        try:
            latex = sp.latex(value)
            if len(latex) <= MAX_FIELD_CHARS:
                self.fields["latex"] = latex
        except Exception:
            pass
        if numeric:
            decimal = _decimal(value, precision)
            if decimal is not None:
                self.fields["numeric"] = self.text(decimal)

    def done(self, **extra):
        self.fields.update(extra)
        self.fields["warnings"] = self.warnings
        return self.fields


def _decimal(value, precision):
    if not isinstance(value, sp.Expr) or value.free_symbols or value.is_Integer:
        return None
    if value.has(sp.oo, sp.zoo, sp.nan) or all(part.is_Integer for part in value.as_real_imag()):
        return None
    try:
        number = sp.N(value, precision)
    except Exception:
        return None
    return _printer.doprint(number) if number.is_number and not number.has(sp.Integral, sp.Sum) else None


def _take(args, name, kind, default=None, required=False):
    value = args.get(name)
    if value is None:
        if required:
            raise MathError("invalid_arguments", f"'{name}' is required")
        return default
    if kind == "math":
        # models send small numbers as JSON numbers as often as strings
        if isinstance(value, bool) or not isinstance(value, (str, int, float)):
            raise MathError("invalid_arguments", f"'{name}' must be a string")
        return value if isinstance(value, str) else repr(value)
    if kind == "int":
        if isinstance(value, bool) or not isinstance(value, int):
            raise MathError("invalid_arguments", f"'{name}' must be an integer")
        return value
    if kind == "list":
        if isinstance(value, (str, int, float)) and not isinstance(value, bool):
            value = [value]
        if not isinstance(value, list) or not value:
            raise MathError("invalid_arguments", f"'{name}' must be a non-empty list")
        if len(value) > MAX_EQUATIONS:
            raise MathError("input_too_large", f"'{name}' has more than {MAX_EQUATIONS} entries")
        return [_take({name: item}, name, "math") for item in value]
    if kind == "dict":
        if not isinstance(value, dict) or len(value) > MAX_EQUATIONS:
            raise MathError("invalid_arguments", f"'{name}' must be an object with at most {MAX_EQUATIONS} entries")
        return {key: _take({name: item}, name, "math") for key, item in value.items()}
    raise AssertionError(kind)


def _precision(args):
    digits = _take(args, "precision", "int", DEFAULT_PRECISION)
    if not 1 <= digits <= MAX_PRECISION:
        raise MathError("invalid_arguments", f"'precision' must be between 1 and {MAX_PRECISION}")
    return digits


def _context(args, functions=None):
    assumptions = args.get("assumptions")
    if assumptions is not None and not isinstance(assumptions, dict):
        raise MathError("invalid_arguments", "'assumptions' must be an object")
    return Context(assumptions, functions)


def _expression(args, context, name="expression"):
    expr = parse_expression(_take(args, name, "math", required=True), context)
    for key, value in (_take(args, "substitutions", "dict") or {}).items():
        expr = expr.subs(context.symbol(key), parse_expression(value, context))
    return expr


def _variable(args, context, expr, name="variable"):
    given = _take(args, name, "math")
    if given is not None:
        return context.symbol(given.strip())
    free = sorted(expr.free_symbols, key=lambda s: s.name)
    if len(free) != 1:
        raise MathError("invalid_arguments", f"'{name}' is required when the expression has {len(free)} variables")
    return free[0]


def _unevaluated(reply, value, kinds, what):
    if isinstance(value, sp.Basic) and value.has(*kinds):
        reply.warnings.append(f"no closed form found for the {what}; the result is left unevaluated")


# expression tool

def _rewrite(function):
    def run(args, reply):
        context = _context(args)
        reply.value(function(_expression(args, context)), _precision(args))
        return reply.done()
    return run


def _apart(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    given = _take(args, "variable", "math")
    result = sp.apart(expr, context.symbol(given)) if given else sp.apart(expr)
    reply.value(result, _precision(args))
    return reply.done()


def _evaluate(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    precision = _precision(args)
    reply.value(sp.nsimplify(expr) if expr.is_Rational else expr, precision, numeric=False)
    reply.fields["numeric"] = reply.text(sp.N(expr, precision))
    if expr.free_symbols:
        reply.warnings.append("the expression still has variables; give them values in 'substitutions'")
    return reply.done()


def _differentiate(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    order = _take(args, "order", "int", 1)
    if not 1 <= order <= 20:
        raise MathError("invalid_arguments", "'order' must be between 1 and 20")
    reply.value(sp.diff(expr, _variable(args, context, expr), order), _precision(args))
    return reply.done()


def _bounds(args, context):
    lower, upper = _take(args, "lower", "math"), _take(args, "upper", "math")
    if (lower is None) != (upper is None):
        raise MathError("invalid_arguments", "'lower' and 'upper' must be given together")
    if lower is None:
        return None
    return parse_expression(lower, context), parse_expression(upper, context)


def _integrate(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    variable = _variable(args, context, expr)
    bounds = _bounds(args, context)
    result = sp.integrate(expr, (variable, *bounds) if bounds else variable)
    _unevaluated(reply, result, (sp.Integral,), "integral")
    reply.value(result, _precision(args))
    if not bounds:
        reply.fields["note"] = "antiderivative, constant of integration omitted"
    return reply.done()


def _ranged(function, kinds, what):
    def run(args, reply):
        context = _context(args)
        expr = _expression(args, context)
        variable = _variable(args, context, expr)
        bounds = _bounds(args, context)
        if bounds is None:
            raise MathError("invalid_arguments", "'lower' and 'upper' are required")
        result = function(expr, (variable, *bounds))
        _unevaluated(reply, result, kinds, what)
        reply.value(result, _precision(args))
        return reply.done()
    return run


def _limit(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    variable = _variable(args, context, expr)
    point = parse_expression(_take(args, "point", "math", required=True), context)
    direction = args.get("direction") or "both"
    if direction not in ("both", "+", "-"):
        raise MathError("invalid_arguments", "'direction' must be \"both\", \"+\" or \"-\"")
    if direction == "both" and point in (sp.oo, -sp.oo):
        direction = "-" if point == sp.oo else "+"
    try:
        result = sp.limit(expr, variable, point, "+-" if direction == "both" else direction)
    except ValueError as error:
        # SymPy raises when the one-sided limits differ
        raise MathError("no_result", str(error)[:300])
    _unevaluated(reply, result, (sp.Limit,), "limit")
    reply.value(result, _precision(args))
    return reply.done()


def _series(args, reply):
    context = _context(args)
    expr = _expression(args, context)
    variable = _variable(args, context, expr)
    point = parse_expression(_take(args, "point", "math", "0"), context)
    order = _take(args, "order", "int", 6)
    if not 1 <= order <= 30:
        raise MathError("invalid_arguments", "'order' must be between 1 and 30")
    result = sp.series(expr, variable, point, order)
    reply.value(result, _precision(args), numeric=False)
    reply.fields["polynomial"] = reply.text(result.removeO())
    return reply.done()


def _transform(function, kind, default_from, default_to):
    def run(args, reply):
        context = _context(args)
        expr = _expression(args, context)
        given = _take(args, "variable", "math")
        source = context.symbol(given or default_from)
        target = context.symbol(_take(args, "transform_variable", "math", default_to))
        result = function(expr, source, target)
        _unevaluated(reply, result, (kind,), "transform")
        reply.value(result, _precision(args), numeric=False)
        return reply.done()
    return run


# solve tool

def _relations(args, context):
    return [parse_relation(text, context) for text in _take(args, "equations", "list", required=True)]


def _unknowns(args, context, relations):
    given = _take(args, "variables", "list")
    if given:
        return [context.symbol(name.strip()) for name in given]
    free = sorted(set().union(*(r.free_symbols for r in relations)), key=lambda s: s.name)
    if not free:
        raise MathError("invalid_arguments", "the equations have no variables")
    return free


def _solution_rows(reply, solutions, precision):
    rows, decimals = [], []
    for solution in reply.items(solutions):
        rows.append({symbol.name: reply.text(value) for symbol, value in solution.items()})
        decimal = {symbol.name: _decimal(value, precision) for symbol, value in solution.items()}
        decimals.append({name: reply.text(text) for name, text in decimal.items() if text is not None})
    reply.fields["solutions"] = rows
    if any(decimals):
        reply.fields["numeric"] = decimals


def _solve(args, reply):
    context = _context(args)
    relations = _relations(args, context)
    unknowns = _unknowns(args, context, relations)
    precision = _precision(args)
    if any(not isinstance(r, sp.Eq) for r in relations):
        if len(unknowns) != 1:
            raise MathError("not_supported", "inequalities are solved for one variable at a time")
        result = sp.reduce_inequalities(relations, unknowns)
        reply.value(result, precision, numeric=False)
        try:
            reply.fields["set"] = reply.text(result.as_set())
        except Exception:
            pass
        return reply.done()
    solutions = sp.solve(relations, unknowns, dict=True)
    reply.value(solutions, precision, numeric=False)
    _solution_rows(reply, solutions, precision)
    if not solutions:
        reply.warnings.append("no solution found; this does not prove that none exists")
    return reply.done(count=len(solutions))


def _solveset(args, reply):
    context = _context(args)
    relations = _relations(args, context)
    unknowns = _unknowns(args, context, relations)
    if len(relations) != 1 or len(unknowns) != 1:
        raise MathError("not_supported", "solveset takes one equation or inequality in one variable")
    domain = args.get("domain") or "complex"
    if domain not in ("complex", "real"):
        raise MathError("invalid_arguments", "'domain' must be \"complex\" or \"real\"")
    relation = relations[0]
    if not isinstance(relation, sp.Eq):
        domain = "real"
    target = relation.lhs - relation.rhs if isinstance(relation, sp.Eq) else relation
    result = sp.solveset(target, unknowns[0], sp.S.Reals if domain == "real" else sp.S.Complexes)
    precision = _precision(args)
    reply.value(result, precision, numeric=False)
    if isinstance(result, sp.FiniteSet):
        _solution_rows(reply, [{unknowns[0]: v} for v in sorted(result, key=sp.default_sort_key)], precision)
    elif isinstance(result, sp.ConditionSet):
        reply.warnings.append("the solution set could not be written explicitly")
    return reply.done(domain=domain)


def _nsolve(args, reply):
    context = _context(args)
    relations = _relations(args, context)
    unknowns = _unknowns(args, context, relations)
    if any(not isinstance(r, sp.Eq) for r in relations) or len(relations) != len(unknowns):
        raise MathError("invalid_arguments", "nsolve needs as many equations as variables")
    guesses = [parse_expression(g, context) for g in _take(args, "initial_guess", "list", required=True)]
    if len(guesses) != len(unknowns) or any(g.free_symbols for g in guesses):
        raise MathError("invalid_arguments", "'initial_guess' needs one number per variable")
    precision = _precision(args)
    residuals = [r.lhs - r.rhs for r in relations]
    if set().union(*(r.free_symbols for r in residuals)) - set(unknowns):
        raise MathError("invalid_arguments", "every symbol must be one of 'variables' for a numerical solve")

    # findroot gets plain closures, never generated code
    def closure(residual):
        def evaluate(*values):
            point = {u: sp.sympify(v) for u, v in zip(unknowns, values)}
            return residual.evalf(precision + 10, subs=point)._to_mpmath(mpmath.mp.prec)
        return evaluate

    with mpmath.workdps(precision + 10):
        start = [g.evalf(precision + 10)._to_mpmath(mpmath.mp.prec) for g in guesses]
        functions = [closure(r) for r in residuals]
        try:
            root = mpmath.findroot(functions[0] if len(functions) == 1 else functions,
                                   start[0] if len(start) == 1 else start)
        except (ValueError, ZeroDivisionError, TypeError) as error:
            raise MathError("no_result", f"the numerical solver did not converge: {str(error)[:200]}")
        values = [root] if len(unknowns) == 1 else list(root)
        solution = {u: sp.sympify(v).evalf(precision) for u, v in zip(unknowns, values)}
    reply.value([solution], precision, numeric=False)
    reply.fields["numeric"] = [{u.name: reply.text(v) for u, v in solution.items()}]
    reply.warnings.append("numerical result near the initial guess; other solutions may exist")
    return reply.done()


def _ode_context(args):
    name = check_identifier((_take(args, "function", "math", "y")).strip())
    variable = check_identifier((_take(args, "variable", "math", "x")).strip())
    context = _context(args, {name: variable})
    return context, context.functions[name](context.function_variables[name])


def _dsolve(args, reply):
    context, function = _ode_context(args)
    relations = _relations(args, context)
    if len(relations) != 1 or not isinstance(relations[0], sp.Eq):
        raise MathError("not_supported", "dsolve takes one differential equation")
    conditions = {}
    for key, value in (_take(args, "initial_conditions", "dict") or {}).items():
        conditions[parse_expression(key, context)] = parse_expression(value, context)
    result = sp.dsolve(relations[0], function, ics=conditions or None)
    solutions = result if isinstance(result, list) else [result]
    reply.value(solutions[0] if len(solutions) == 1 else solutions, _precision(args), numeric=False)
    reply.fields["solutions"] = [reply.text(s) for s in reply.items(solutions)]
    return reply.done()


# matrix tool

def _matrix(args, context, name, required=True):
    rows = args.get(name)
    if rows is None:
        if required:
            raise MathError("invalid_arguments", f"'{name}' is required")
        return None
    if not isinstance(rows, list) or not rows:
        raise MathError("invalid_arguments", f"'{name}' must be a list of rows")
    if not isinstance(rows[0], list):
        rows = [[entry] for entry in rows]
    width = len(rows[0])
    if len(rows) > MAX_MATRIX_SIDE or width > MAX_MATRIX_SIDE:
        raise MathError("input_too_large", f"matrices are limited to {MAX_MATRIX_SIDE} by {MAX_MATRIX_SIDE}")
    if width == 0 or any(not isinstance(row, list) or len(row) != width for row in rows):
        raise MathError("invalid_arguments", f"every row of '{name}' must have the same length")
    return sp.Matrix([[parse_expression(_take({name: entry}, name, "math", required=True), context)
                       for entry in row] for row in rows])


def _matrix_rows(reply, matrix):
    return [[reply.text(entry) for entry in matrix.row(i)] for i in range(matrix.rows)]


def _matrix_value(reply, matrix, precision):
    reply.value(matrix, precision, numeric=False)
    reply.fields["matrix"] = _matrix_rows(reply, matrix)


def _square(matrix):
    if matrix.rows != matrix.cols:
        raise MathError("invalid_arguments", "the matrix must be square")


def _matrix_operation(operation):
    def run(args, reply):
        context = _context(args)
        matrix = _matrix(args, context, "matrix")
        precision = _precision(args)
        if operation == "determinant":
            _square(matrix)
            reply.value(sp.simplify(matrix.det()), precision)
        elif operation == "inverse":
            _square(matrix)
            if sp.simplify(matrix.det()) == 0:
                raise MathError("no_result", "the matrix is singular and has no inverse")
            _matrix_value(reply, matrix.inv().applyfunc(sp.simplify), precision)
        elif operation == "transpose":
            _matrix_value(reply, matrix.T, precision)
        elif operation == "rank":
            reply.value(sp.Integer(matrix.rank()), precision)
        elif operation == "rref":
            reduced, pivots = matrix.rref()
            _matrix_value(reply, reduced, precision)
            reply.fields["pivot_columns"] = list(pivots)
        elif operation == "nullspace":
            basis = matrix.nullspace()
            reply.value(basis, precision, numeric=False)
            reply.fields["vectors"] = [[reply.text(e) for e in vector] for vector in reply.items(basis)]
        elif operation == "eigenvalues":
            _square(matrix)
            values = matrix.eigenvals()
            ordered = sorted(values, key=sp.default_sort_key)
            reply.value(ordered, precision, numeric=False)
            reply.fields["eigenvalues"] = [
                {"value": reply.text(v), "multiplicity": int(values[v]),
                 **({"numeric": reply.text(d)} if (d := _decimal(v, precision)) else {})}
                for v in reply.items(ordered)]
        elif operation == "eigenvectors":
            _square(matrix)
            triples = sorted(matrix.eigenvects(), key=lambda t: sp.default_sort_key(t[0]))
            reply.value([t[0] for t in triples], precision, numeric=False)
            reply.fields["eigenvectors"] = [
                {"eigenvalue": reply.text(value), "multiplicity": int(multiplicity),
                 "vectors": [[reply.text(sp.simplify(e)) for e in vector] for vector in vectors]}
                for value, multiplicity, vectors in reply.items(triples)]
        elif operation == "multiply":
            other = _matrix(args, context, "other")
            if matrix.cols != other.rows:
                raise MathError("invalid_arguments", "the column count of 'matrix' must equal the row count of 'other'")
            _matrix_value(reply, (matrix * other).applyfunc(sp.expand), precision)
        elif operation == "solve":
            other = _matrix(args, context, "other")
            if other.rows != matrix.rows:
                raise MathError("invalid_arguments", "'other' needs one row per row of 'matrix'")
            unknowns = sp.symbols(f"x1:{matrix.cols + 1}")
            solutions = sp.linsolve((matrix, other), *unknowns)
            if not solutions:
                raise MathError("no_result", "the linear system has no solution")
            solution = next(iter(solutions))
            reply.value(sp.Matrix(solution), precision, numeric=False)
            reply.fields["solution"] = [reply.text(e) for e in solution]
            if any(e.free_symbols & set(unknowns) for e in solution):
                reply.warnings.append("infinitely many solutions; x1, x2, ... are free parameters")
        return reply.done()
    return run


# verify tool

def _is_zero(expr):
    """True, False, or None when SymPy cannot decide."""
    simplified = sp.simplify(expr)
    if simplified == 0:
        return True, simplified
    verdict = simplified.equals(0)
    if verdict is None and not simplified.free_symbols:
        verdict = bool(abs(sp.N(simplified, 50)) < sp.Float("1e-40"))
    return verdict, simplified


def _equivalent(args, reply):
    context = _context(args)
    left = _expression(args, context, "left")
    right = _expression(args, context, "right")
    verdict, difference = _is_zero(left - right)
    reply.fields["equivalent"] = verdict
    reply.fields["difference"] = reply.text(difference)
    try:
        reply.fields["difference_latex"] = reply.text(sp.latex(difference))
    except Exception:
        pass
    if verdict is None:
        reply.warnings.append("could not decide; the difference did not simplify to zero")
    return reply.done()


def _check_solution(args, reply):
    functions = None
    if args.get("function") is not None:
        context, function = _ode_context(args)
        functions = {function.func.__name__: function}
    else:
        context = _context(args)
    relations = _relations(args, context)
    solution = _take(args, "solution", "dict", required=True)
    replacements = {}
    for key, value in solution.items():
        key = key.strip()
        target = functions[key] if functions and key in functions else context.symbol(key)
        replacements[target] = parse_expression(value, context)

    checks, satisfied = [], True
    for relation in relations:
        if isinstance(relation, sp.Eq):
            # substituting into the Eq itself would collapse it to a bare True or False
            verdict, residual = _is_zero((relation.lhs - relation.rhs).subs(replacements).doit())
            checks.append({"equation": reply.text(relation), "satisfied": verdict,
                           "residual": reply.text(residual)})
        else:
            outcome = sp.simplify(relation.subs(replacements).doit())
            verdict = True if outcome == sp.true else False if outcome == sp.false else None
            checks.append({"equation": reply.text(relation), "satisfied": verdict,
                           "residual": reply.text(outcome)})
        if verdict is None:
            reply.warnings.append("could not decide one of the checks")
        satisfied = None if (verdict is None and satisfied) else (satisfied and verdict)
    return reply.done(satisfied=satisfied, checks=checks)


OPERATIONS = {
    "simplify": _rewrite(sp.simplify),
    "expand": _rewrite(sp.expand),
    "factor": _rewrite(sp.factor),
    "cancel": _rewrite(sp.cancel),
    "together": _rewrite(sp.together),
    "apart": _apart,
    "evaluate": _evaluate,
    "differentiate": _differentiate,
    "integrate": _integrate,
    "limit": _limit,
    "series": _series,
    "summation": _ranged(sp.summation, (sp.Sum,), "sum"),
    "product": _ranged(sp.product, (sp.Product,), "product"),
    "laplace_transform": _transform(
        lambda f, t, s: sp.laplace_transform(f, t, s, noconds=True), sp.LaplaceTransform, "t", "s"),
    "inverse_laplace_transform": _transform(
        sp.inverse_laplace_transform, sp.InverseLaplaceTransform, "s", "t"),
    "fourier_transform": _transform(sp.fourier_transform, sp.FourierTransform, "x", "k"),
    "inverse_fourier_transform": _transform(
        sp.inverse_fourier_transform, sp.InverseFourierTransform, "k", "x"),
    "solve": _solve,
    "solveset": _solveset,
    "nsolve": _nsolve,
    "dsolve": _dsolve,
    **{name: _matrix_operation(name) for name in (
        "determinant", "inverse", "transpose", "rank", "rref", "nullspace",
        "eigenvalues", "eigenvectors", "multiply")},
    "linear_solve": _matrix_operation("solve"),
    "equivalent": _equivalent,
    "solution": _check_solution,
}


def failure(operation, code, message):
    return {"success": False, "operation": operation, "error": {"code": code, "message": message}}


def run(operation, arguments):
    if not isinstance(arguments, dict):
        return failure(operation, "invalid_arguments", "arguments must be an object")
    handler = OPERATIONS.get(operation) if isinstance(operation, str) else None
    if handler is None:
        return failure(str(operation)[:40], "unknown_operation",
                       "'operation' must be one of: " + ", ".join(OPERATIONS))
    try:
        return handler(arguments, Reply(operation))
    except MathError as error:
        return failure(operation, error.code, error.message)
    except RecursionError:
        return failure(operation, "too_large", "the expression is too complex to process")
    except NotImplementedError as error:
        return failure(operation, "not_supported", f"SymPy cannot do this: {str(error)[:300]}")
    except (ValueError, TypeError, ArithmeticError, AttributeError, KeyError, IndexError) as error:
        return failure(operation, "math_error", f"{type(error).__name__}: {str(error)[:300]}")
