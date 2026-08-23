"""Direct server-side tests for `document_service.jac`, following the same pattern
`internal/service-registry-spike`'s `config_service_tests.jac` established for Phase 0's spike: idempotent
lookup, and the RPC surface the client actually calls."""

test "get_document_buffer is idempotent -- repeated lookup returns the same cached instance" {
    _reset_document_buffer_cache_for_tests();
    first = get_document_buffer();
    second = get_document_buffer();
    assert first == second;
}

test "get_document_lines returns the seeded content, split into lines" {
    _reset_document_buffer_cache_for_tests();
    lines = get_document_lines();
    assert lines[0] == "Welcome to jac-studio's editor core.";
    assert len(lines) > 1;
}

test "apply_document_edit inserts text and returns the updated lines" {
    _reset_document_buffer_cache_for_tests();
    lines = apply_document_edit(1, 1, 1, 1, "Hi! ");
    assert lines[0].startswith("Hi! Welcome");
}

test "apply_document_edit deletes a range when text is empty" {
    _reset_document_buffer_cache_for_tests();
    lines = apply_document_edit(1, 1, 1, 1, "X");
    assert lines[0].startswith("XWelcome");
    lines = apply_document_edit(1, 1, 1, 2, "");
    assert lines[0].startswith("Welcome");
}

test "apply_document_edit can insert a newline, splitting a line in two" {
    _reset_document_buffer_cache_for_tests();
    original_lines = get_document_lines();
    original_line_count = len(original_lines);
    original_first_line = original_lines[0];

    lines = apply_document_edit(1, 8, 1, 8, "\n");

    assert len(lines) == original_line_count + 1;
    assert lines[0] == original_first_line[0:7];
    assert lines[1] == original_first_line[7:];
}
