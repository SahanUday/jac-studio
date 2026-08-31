test "a channel starts empty and appears in list_channels only once a line is logged" {
    _reset_output_channels_cache_for_tests();

    assert list_channels() == [];
    assert get_channel_content("Tasks") == "";

    append_log("Tasks", "starting build");

    assert list_channels() == ["Tasks"];
    assert get_channel_content("Tasks") == "starting build";
}

test "multiple lines on one channel join in append order" {
    _reset_output_channels_cache_for_tests();

    append_log("Tasks", "line 1");
    append_log("Tasks", "line 2");
    append_log("Tasks", "line 3");

    assert get_channel_content("Tasks") == "line 1\nline 2\nline 3";
}

test "channels are independent -- appending to one doesn't affect another" {
    _reset_output_channels_cache_for_tests();

    append_log("Tasks", "task output");
    append_log("Git", "git output");

    assert get_channel_content("Tasks") == "task output";
    assert get_channel_content("Git") == "git output";
    assert set(list_channels()) == {"Tasks", "Git"};
}

test "clear_channel empties a channel's lines without removing it from list_channels" {
    _reset_output_channels_cache_for_tests();
    append_log("Tasks", "line 1");

    clear_channel("Tasks");

    assert get_channel_content("Tasks") == "";
    assert list_channels() == ["Tasks"];
}

test "clear_channel on a channel that was never logged to is a harmless no-op" {
    _reset_output_channels_cache_for_tests();

    clear_channel("NeverLogged");

    assert list_channels() == [];
}

test "a channel past the line cap drops the oldest lines, keeping the newest" {
    _reset_output_channels_cache_for_tests();

    for i in range(_MAX_LINES_PER_CHANNEL + 10) {
        append_log("Tasks", "line " + str(i));
    }

    content_lines = get_channel_content("Tasks").split("\n");
    assert len(content_lines) == _MAX_LINES_PER_CHANNEL;
    assert content_lines[0] == "line 10";
    assert content_lines[-1] == "line " + str(_MAX_LINES_PER_CHANNEL + 9);
}
