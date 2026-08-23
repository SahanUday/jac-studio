"""Verification gate: runs `jac check` then `jac test` against a ported module, as real
subprocesses of the `jac` CLI itself. This is the trust boundary -- nothing lands without
passing. Deliberately dumb: whatever `jac` itself considers a failure (nonzero exit), we treat
as a failure. No independent judgment about which warnings matter -- that's the compiler's job.
"""

import subprocess;

obj VerificationResult {
    has passed: bool;
    has check_output: str;
    has test_output: str;
    has failure_stage: str = "";   # "" | "check" | "test"
}

def run_check(jac_path: str) -> tuple[bool, str] {
    result = subprocess.run(["jac", "check", jac_path], capture_output=True, text=True);
    return (result.returncode == 0, result.stdout + result.stderr);
}

def run_test(jac_path: str) -> tuple[bool, str] {
    result = subprocess.run(["jac", "test", jac_path], capture_output=True, text=True);
    return (result.returncode == 0, result.stdout + result.stderr);
}

def verify(jac_path: str) -> VerificationResult {
    (check_ok, check_out) = run_check(jac_path);
    if not check_ok {
        return VerificationResult(
            passed=False, check_output=check_out, test_output="", failure_stage="check"
        );
    }
    (test_ok, test_out) = run_test(jac_path);
    if not test_ok {
        return VerificationResult(
            passed=False, check_output=check_out, test_output=test_out, failure_stage="test"
        );
    }
    return VerificationResult(passed=True, check_output=check_out, test_output=test_out);
}
