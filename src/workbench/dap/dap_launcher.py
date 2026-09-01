"""Spawned by dap_client.jac as `<embedded-python> -m debugpy --listen <host:port>
--wait-for-client dap_launcher.py <file.jac>`, never imported directly.

Plain Python, not Jac: this needs to run under `python -m debugpy` as an ordinary Python
entry script (debugpy's own `--wait-for-client` machinery execs it via `runpy.run_path`), so
it has to already be a `.py` file on disk debugpy can hand to `runpy` -- a `.jac` file has no
such role, jaclang's own compiler is what this script calls to get one.

Mirrors exactly what `jac run --debug` itself does to hand a `.jac` file's compiled bytecode
to a Python-level debugger (`jaclang/cli/commands/impl/execution.impl.jac`'s `debug()`:
`JacProgram().compile(filename).gen.py_bytecode`, `marshal.loads`, wrap as a `FunctionType`,
call it) -- confirmed live (see tracker entry
`2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source`) that
the resulting code object's `co_filename` is the literal `.jac` path and its line table maps
1:1 to real `.jac` source lines, which is the only reason a standard `sys.settrace`-based
debugger (debugpy included) can set breakpoints and show variables against `.jac` source at
all, with zero translation step of its own.
"""

import marshal
import sys
import types


def main() -> None:
    filename = sys.argv[1]
    from jaclang.compiler.driver.program import JacProgram

    program = JacProgram().compile(filename)
    bytecode = program.gen.py_bytecode
    if not bytecode:
        print(f"Error while generating bytecode in {filename}.", file=sys.stderr)
        sys.exit(1)
    code = marshal.loads(bytecode)
    func = types.FunctionType(code, {"__name__": "__main__"})
    func()


if __name__ == "__main__":
    main()
