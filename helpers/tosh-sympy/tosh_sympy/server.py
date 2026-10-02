# ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
# Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""MCP server over stdio for the SymPy tools.

This process never imports SymPy. It starts the worker on the first call, kills it when a
call runs past its time or memory budget, and lets it go after a while without use.
"""

import ctypes
import json
import os
import select
import signal
import subprocess
import sys
import time

HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HOME)

from tosh_sympy import schema  # noqa: E402

VERSION = "1.0.0"
PROTOCOL = "2024-11-05"
MAX_REQUEST_BYTES = 64 * 1024
MAX_REPLY_BYTES = 96 * 1024
STARTUP_SECONDS = 30


def _setting(name, default, low, high):
    try:
        return min(max(float(os.environ.get(name, default)), low), high)
    except ValueError:
        return default


TIMEOUT_SECONDS = _setting("TOSH_SYMPY_TIMEOUT_MS", 15000, 100, 20000) / 1000
# after a timeout a fresh worker gets this long to say what it still can about the request
RECOVERY_SECONDS = 5
# SymPy's heuristics walk sets, so with Python's random string hashing the same integral
# takes under a second in one process and never finishes in the next. A fixed seed makes
# every worker behave the same.
HASH_SEED = "1"
MEMORY_LIMIT = int(_setting("TOSH_SYMPY_MEMORY_MB", 1024, 128, 16384)) * 1024 * 1024
IDLE_SECONDS = _setting("TOSH_SYMPY_IDLE_SECONDS", 300, 1, 86400)


def _failure(operation, code, message):
    return {"success": False, "operation": operation, "error": {"code": code, "message": message}}


class _Footprint:
    """Physical memory of a child, read through libproc."""

    def __init__(self):
        self.call = None
        if sys.platform == "darwin":
            try:
                self.call = ctypes.CDLL("/usr/lib/libproc.dylib").proc_pid_rusage
            except (OSError, AttributeError):
                pass
        # rusage_info_v2: a 16 byte uuid, then 64 bit counters
        self.buffer = (ctypes.c_uint64 * 40)()

    def bytes(self, pid):
        if self.call is None or self.call(pid, 2, ctypes.byref(self.buffer)) != 0:
            return 0
        return self.buffer[9]  # ri_phys_footprint


class Worker:
    def __init__(self):
        self.process = None
        self.buffer = b""
        self.footprint = _Footprint()
        self.last_used = time.monotonic()

    def alive(self):
        return self.process is not None and self.process.poll() is None

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait()
            for stream in (self.process.stdin, self.process.stdout):
                try:
                    stream.close()
                except OSError:
                    pass
        self.process = None
        self.buffer = b""

    def start(self):
        self.stop()
        # -P -s instead of -I: the environment is the two variables below and nothing else,
        # and the hash seed has to get through
        self.process = subprocess.Popen(
            [sys.executable, "-P", "-s", "-B", os.path.join(HOME, "tosh_sympy", "worker.py")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            cwd="/", close_fds=True,
            env={"PYTHONHASHSEED": HASH_SEED,
                 "TOSH_SYMPY_BACKSTOP_SECONDS": str(int(TIMEOUT_SECONDS) + 5)})
        ready = self._read(time.monotonic() + STARTUP_SECONDS)
        if not isinstance(ready, dict) or not ready.get("ready"):
            self.stop()
            raise RuntimeError("the SymPy runtime did not start")

    def _read(self, deadline):
        """One reply line, or a string naming why there is none."""
        descriptor = self.process.stdout.fileno()
        while b"\n" not in self.buffer:
            if time.monotonic() >= deadline:
                return "timeout"
            if self.footprint.bytes(self.process.pid) > MEMORY_LIMIT:
                return "memory_limit"
            readable, _, _ = select.select([descriptor], [], [], 0.05)
            if not readable:
                continue
            chunk = os.read(descriptor, 65536)
            if not chunk:
                return "memory_limit" if self.process.wait() == 86 else "worker_crashed"
            self.buffer += chunk
            if len(self.buffer) > MAX_REPLY_BYTES:
                return "output_too_large"
        line, _, self.buffer = self.buffer.partition(b"\n")
        try:
            return json.loads(line)
        except ValueError:
            return "worker_crashed"

    def call(self, name, arguments):
        operation = arguments.get("operation") if isinstance(arguments, dict) else None
        operation = operation if isinstance(operation, str) else None
        request = json.dumps({"tool": name, "arguments": arguments}).encode() + b"\n"
        if len(request) > MAX_REQUEST_BYTES:
            return _failure(operation, "input_too_large", f"the request is larger than {MAX_REQUEST_BYTES} bytes")
        try:
            if not self.alive():
                self.start()
            self.process.stdin.write(request)
            self.process.stdin.flush()
        except (OSError, RuntimeError) as error:
            self.stop()
            return _failure(operation, "runtime_unavailable", str(error)[:300])
        reply = self._read(time.monotonic() + TIMEOUT_SECONDS)
        self.last_used = time.monotonic()
        if isinstance(reply, dict):
            return reply
        self.stop()
        if reply == "timeout":
            return self._recover(name, arguments, operation)
        messages = {
            "memory_limit": f"the calculation needed more than {MEMORY_LIMIT // (1024 * 1024)} MB and was stopped",
            "output_too_large": "the result is too large to return",
            "worker_crashed": "the SymPy runtime stopped unexpectedly",
        }
        return _failure(operation, reply, messages[reply])


    def _recover(self, name, arguments, operation):
        """The request is dead. A new worker reports what is known: at least that it timed out."""
        best = {"success": False, "operation": operation, "timed_out": True, "warnings": [],
                "error": {"code": "timeout", "message":
                          f"The calculation did not finish within the {TIMEOUT_SECONDS:g} s computation budget."}}
        try:
            self.start()
            self.process.stdin.write(json.dumps({"tool": name, "arguments": arguments,
                                                 "after_timeout": TIMEOUT_SECONDS}).encode() + b"\n")
            self.process.stdin.flush()
        except (OSError, RuntimeError):
            self.stop()
            return best
        deadline = time.monotonic() + RECOVERY_SECONDS
        while True:
            reply = self._read(deadline)
            if not isinstance(reply, dict):
                self.stop()
                return best
            if "progress" not in reply:
                self.last_used = time.monotonic()
                return reply
            best = reply["progress"]


def _respond(message_id, result=None, error=None):
    message = {"jsonrpc": "2.0", "id": message_id}
    if error is not None:
        message["error"] = error
    else:
        message["result"] = result
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def _handle(message, worker):
    method, message_id = message.get("method"), message.get("id")
    if message_id is None:
        return
    if method == "initialize":
        _respond(message_id, {
            "protocolVersion": PROTOCOL,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "tosh-sympy", "version": VERSION},
        })
    elif method == "ping":
        _respond(message_id, {})
    elif method == "tools/list":
        _respond(message_id, {"tools": schema.definitions()})
    elif method == "tools/call":
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        reply = worker.call(params.get("name"), params.get("arguments") or {})
        _respond(message_id, {
            "content": [{"type": "text", "text": json.dumps(reply)}],
            # a request that ran out of time or has no closed form was still a valid call
            "isError": not reply.get("success", False) and "timed_out" not in reply,
        })
    else:
        _respond(message_id, error={"code": -32601, "message": f"method not found: {str(method)[:60]}"})


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, lambda *_: sys.exit(0))
    worker = Worker()
    stdin = sys.stdin.buffer
    descriptor = stdin.fileno()
    pending = b""
    try:
        while True:
            readable, _, _ = select.select([descriptor], [], [], 5.0)
            if not readable:
                if worker.alive() and time.monotonic() - worker.last_used > IDLE_SECONDS:
                    worker.stop()
                continue
            chunk = os.read(descriptor, 65536)
            if not chunk:
                break
            pending += chunk
            if len(pending) > 2 * MAX_REQUEST_BYTES and b"\n" not in pending:
                pending = b""
                continue
            while b"\n" in pending:
                line, _, pending = pending.partition(b"\n")
                if not line.strip():
                    continue
                try:
                    message = json.loads(line)
                except ValueError:
                    _respond(None, error={"code": -32700, "message": "parse error"})
                    continue
                if isinstance(message, dict):
                    _handle(message, worker)
    finally:
        worker.stop()


if __name__ == "__main__":
    main()
