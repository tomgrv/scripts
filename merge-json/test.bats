#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "merge-json merges a source object into the target file" {
    target=$(mktemp --suffix=.json)
    echo '{"a":1}' >"$target"
    run bash -c "echo '{\"b\":2}' | merge-json '$target' -"
    [ "$status" -eq 0 ]
    run cat "$target"
    rm -f "$target"
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}
