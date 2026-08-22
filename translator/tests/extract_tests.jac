"""Tests for extract/extract.mjs, via src/extract.jac's Jac wrapper -- asserts the JSON shape
stays stable for representative TS input (a plain exported function, and a class with a doc
comment) rather than mocking the Node subprocess out from under the thing being tested.
"""

import os;
import tempfile;

import from src.extract { run_extraction }

def write_temp(dirpath: str, name: str, content: str) -> str {
    path = os.path.join(dirpath, name);
    with open(path, "w", encoding="utf-8") as f {
        f.write(content);
    }
    return path;
}

test "extraction reports imports and an exported function's signature" {
    with tempfile.TemporaryDirectory() as tmpdir {
        source = write_temp(
            tmpdir, "sample.ts",
            "import { helper } from './util.js';\n\n"
            "export function add(a: number, b: number): number {\n    return a + b;\n}\n",
        );

        data = run_extraction(source);
        imports = data["source"]["imports"];
        symbols = data["source"]["symbols"];

        assert len(imports) == 1;
        assert imports[0]["from"] == "./util.js";
        assert "helper" in (imports[0]["names"] as list);

        assert len(symbols) == 1;
        assert symbols[0]["kind"] == "function";
        assert symbols[0]["name"] == "add";
        assert "a: number, b: number" in (symbols[0]["signature"] as str);
    }
}

test "extraction captures a class's members, signatures, and doc comments" {
    with tempfile.TemporaryDirectory() as tmpdir {
        source = write_temp(
            tmpdir, "widget.ts",
            "export class Widget {\n"
            "    /**\n"
            "     * The widget's display name.\n"
            "     */\n"
            "    private name: string;\n\n"
            "    public getName(): string {\n"
            "        return this.name;\n"
            "    }\n"
            "}\n",
        );

        data = run_extraction(source);
        symbols = data["source"]["symbols"];

        assert len(symbols) == 1;
        assert symbols[0]["kind"] == "class";
        assert symbols[0]["name"] == "Widget";

        member_names = [m["name"] for m in symbols[0]["members"]];
        assert "name" in member_names;
        assert "getName" in member_names;

        name_member = [m for m in symbols[0]["members"] if m["name"] == "name"][0];
        assert "display name" in (name_member["doc"] as str);
    }
}

test "extraction runs against a test file too when one is given" {
    with tempfile.TemporaryDirectory() as tmpdir {
        source = write_temp(tmpdir, "thing.ts", "export function noop(): void {}\n");
        test_file = write_temp(tmpdir, "thing.test.ts", "export function checkNoop(): void {}\n");

        data = run_extraction(source, test_file);
        assert "test" in data;
        assert data["test"]["basename"] == "thing.test.ts";
        assert data["test"]["symbols"][0]["name"] == "checkNoop";
    }
}
