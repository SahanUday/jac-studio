"""Tests for src/verify.jac -- the verification gate, on synthetic fixture .jac modules.

Runs real `jac check`/`jac test` subprocesses against small throwaway fixtures rather than
mocking the subprocess boundary -- the whole point of this gate is that it defers to `jac`
itself, so a test that mocked the subprocess out wouldn't actually verify the gate's contract.
"""

import os;
import tempfile;

import from src.verify { verify }

def write_temp(dirpath: str, name: str, content: str) -> str {
    path = os.path.join(dirpath, name);
    with open(path, "w", encoding="utf-8") as f {
        f.write(content);
    }
    return path;
}

test "a module with a passing test verifies clean" {
    with tempfile.TemporaryDirectory() as tmpdir {
        mod_path = write_temp(
            tmpdir, "good.jac",
            "def add(a: int, b: int) -> int {\n    return a + b;\n}\n",
        );
        write_temp(tmpdir, "good.test.jac", "test \"add works\" {\n    assert add(2, 3) == 5;\n}\n");

        result = verify(mod_path);
        assert result.passed;
        assert result.failure_stage == "";
    }
}

test "a module that fails jac check is caught at the check stage" {
    with tempfile.TemporaryDirectory() as tmpdir {
        # 'match' is a reserved keyword used as a bare identifier here -- a real jac check error.
        mod_path = write_temp(tmpdir, "broken.jac", "def bad() -> int {\n    match = 1;\n    return match;\n}\n");

        result = verify(mod_path);
        assert not result.passed;
        assert result.failure_stage == "check";
        assert result.check_output;
        assert result.test_output == "";
    }
}

test "a module that compiles but fails its own test is caught at the test stage" {
    with tempfile.TemporaryDirectory() as tmpdir {
        mod_path = write_temp(
            tmpdir, "wrong.jac",
            "def add(a: int, b: int) -> int {\n    return a - b;\n}\n",
        );
        write_temp(tmpdir, "wrong.test.jac", "test \"add works\" {\n    assert add(2, 3) == 5;\n}\n");

        result = verify(mod_path);
        assert not result.passed;
        assert result.failure_stage == "test";
        assert result.check_output;
        assert result.test_output;
    }
}

test "a module with no ported test file fails verification, does not silently pass" {
    with tempfile.TemporaryDirectory() as tmpdir {
        # No <mod>.test.jac annex and no inline test {} block -- `jac test` exits nonzero
        # ("No tests ran") rather than vacuously succeeding. This is the property the whole
        # verification gate depends on: a translated module can't land without real ported
        # tests just because it happens to compile cleanly.
        mod_path = write_temp(
            tmpdir, "untested.jac",
            "def add(a: int, b: int) -> int {\n    return a + b;\n}\n",
        );

        result = verify(mod_path);
        assert not result.passed;
        assert result.failure_stage == "test";
        assert "no tests" in result.test_output.lower();
    }
}
