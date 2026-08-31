import os;
import tempfile;
import from src.workbench.workspace.workspace_service { _reset_workspace_cache_for_tests, open_workspace }

def make_fixture -> str {
    fixture_root = tempfile.mkdtemp();
    with open(os.path.join(fixture_root, "hello.txt"), "w") as f {
        f.write("first line\nHello World\nthird line\n");
    }
    with open(os.path.join(fixture_root, "other.txt"), "w") as f {
        f.write("nothing interesting here\nhello again, world\n");
    }
    os.makedirs(os.path.join(fixture_root, "sub"));
    with open(os.path.join(fixture_root, "sub", "nested.txt"), "w") as f {
        f.write("hello from a nested file\n");
    }
    with open(os.path.join(fixture_root, "binary.dat"), "wb") as f {
        f.write(bytes([0, 159, 146, 150, 255, 0, 1, 2]));
    }
    return fixture_root;
}

def open_fixture -> str {
    fixture_root = make_fixture();
    _reset_workspace_cache_for_tests();
    open_workspace(fixture_root);
    return fixture_root;
}

test "an empty or blank query returns no results" {
    open_fixture();

    assert search_in_files("") == [];
    assert search_in_files("   ") == [];
}

test "search is case-insensitive and finds matches across multiple files" {
    open_fixture();

    results = search_in_files("hello");

    names = set([r["name"] for r in results]);
    assert names == {"hello.txt", "other.txt", "nested.txt"};
}

test "each result reports the matching line, 1-based column, and a preview" {
    open_fixture();

    results = search_in_files("Hello World");
    hello_result = [r for r in results if r["name"] == "hello.txt"][0];

    assert len(hello_result["matches"]) == 1;
    first_match = hello_result["matches"][0];
    assert first_match["line"] == 2;
    assert first_match["column"] == 1;
    assert first_match["preview"] == "Hello World";
}

test "a file with multiple matching lines reports every match" {
    open_fixture();

    results = search_in_files("line");
    hello_result = [r for r in results if r["name"] == "hello.txt"][0];

    assert len(hello_result["matches"]) == 2;
    assert hello_result["matches"][0]["line"] == 1;
    assert hello_result["matches"][1]["line"] == 3;
}

test "a query matching nothing returns an empty list, not an error" {
    open_fixture();

    assert search_in_files("this string appears nowhere") == [];
}

test "a binary file is skipped, not returned or crashing the search" {
    open_fixture();

    results = search_in_files("hello");

    assert "binary.dat" not in [r["name"] for r in results];
}

test "no open workspace returns an empty list" {
    _reset_workspace_cache_for_tests();

    assert search_in_files("hello") == [];
}
