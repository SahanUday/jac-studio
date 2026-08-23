"""Tests for src/eligibility.jac -- the guard's mechanical checks, on synthetic fixtures so
they're reproducible without the vscode checkout present. (The guard has also been validated by
hand against the real targets -- see manifest.toml and internal/translator/README.md.)
"""

import os;
import tempfile;

import from src.eligibility { check_eligibility, find_test_file }

def write_temp(dirpath: str, name: str, content: str) -> str {
    path = os.path.join(dirpath, name);
    with open(path, "w", encoding="utf-8") as f {
        f.write(content);
    }
    return path;
}

test "a small, pure module with a co-located test is eligible" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        test_dir = os.path.join(tmpdir, "test");
        os.makedirs(src_dir);
        os.makedirs(test_dir);

        source = write_temp(src_dir, "pureMath.ts", "export function add(a: number, b: number) { return a + b; }\n");
        write_temp(test_dir, "pureMath.test.ts", "// trivial test\n");

        result = check_eligibility(source, test_dir);
        assert result.eligible;
        assert result.reasons == [];
        assert result.test_path.endswith("pureMath.test.ts");
    }
}

test "a module referencing a real DOM API call is rejected" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        os.makedirs(src_dir);
        source = write_temp(
            src_dir, "domThing.ts",
            "export function paint() { document.getElementById('x'); }\n",
        );
        result = check_eligibility(source, src_dir);
        assert not result.eligible;
        assert any("banned DOM" in r for r in result.reasons);
    }
}

test "the word 'document' in prose does not false-positive" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        test_dir = os.path.join(tmpdir, "test");
        os.makedirs(src_dir);
        os.makedirs(test_dir);
        source = write_temp(
            src_dir, "prose.ts",
            "// node start offset in document.\nexport function noop() {}\n",
        );
        write_temp(test_dir, "prose.test.ts", "// trivial\n");
        result = check_eligibility(source, test_dir);
        assert result.eligible;
    }
}

test "a module importing a /browser/ path segment is rejected" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        os.makedirs(src_dir);
        source = write_temp(
            src_dir, "usesBrowser.ts",
            "import { Foo } from '../browser/foo.js';\nexport const x = 1;\n",
        );
        result = check_eligibility(source, src_dir);
        assert not result.eligible;
        assert any("banned path segment" in r for r in result.reasons);
    }
}

test "a module over the line threshold is rejected" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        os.makedirs(src_dir);
        big_content = "\n".join(["export const x = 1;" for _ in range(50)]);
        source = write_temp(src_dir, "big.ts", big_content);
        result = check_eligibility(source, src_dir, max_lines=10);
        assert not result.eligible;
        assert any("too large" in r for r in result.reasons);
    }
}

test "an explicit test_file_override bypasses basename search" {
    with tempfile.TemporaryDirectory() as tmpdir {
        src_dir = os.path.join(tmpdir, "src");
        other_dir = os.path.join(tmpdir, "elsewhere");
        os.makedirs(src_dir);
        os.makedirs(other_dir);
        source = write_temp(src_dir, "inner.ts", "export const x = 1;\n");
        override_test = write_temp(other_dir, "outerWrapper.test.ts", "// covers inner.ts too\n");

        result = check_eligibility(source, src_dir, test_file_override=override_test);
        assert result.eligible;
        assert result.test_path == override_test;
    }
}

test "find_test_file searches by basename, not path-mirroring" {
    with tempfile.TemporaryDirectory() as tmpdir {
        test_dir = os.path.join(tmpdir, "test", "common", "viewModel");
        os.makedirs(test_dir);
        write_temp(test_dir, "oddlyPlaced.test.ts", "// lives somewhere the source dir doesn't mirror\n");

        found = find_test_file(os.path.join(tmpdir, "src", "common", "model", "oddlyPlaced.ts"), os.path.join(tmpdir, "test"));
        assert found.endswith("oddlyPlaced.test.ts");
    }
}
