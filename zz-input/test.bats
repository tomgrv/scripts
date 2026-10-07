#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-input is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-input)"
    [ "$status" -eq 0 ]
}

@test "zz-input reads a literal argument" {
    run zz-input "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "zz-input reads a file argument" {
    tmp=$(mktemp)
    echo "from-file" >"$tmp"
    run zz-input "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-file"* ]]
}

@test "zz-input reads stdin when no argument given" {
    run bash -c 'echo "from-stdin" | zz-input'
    [ "$status" -eq 0 ]
    [ "$output" = "from-stdin" ]
}

@test "zz-input treats a non-existent path as a literal string, not an error" {
    run zz-input "/no/such/file/here"
    [ "$status" -eq 0 ]
    [ "$output" = "/no/such/file/here" ]
}

@test "zz-input reading a file logs which file it read from, to stderr" {
    tmp=$(mktemp)
    echo "contents" >"$tmp"
    run bash -c "zz-input '$tmp' 2>&1 1>/dev/null"
    rm -f "$tmp"
    [[ "$output" == *"$tmp"* ]]
}

@test "zz-input preserves multi-line file content" {
    tmp=$(mktemp)
    printf 'line1\nline2\nline3\n' >"$tmp"
    run bash -c "zz-input '$tmp' 2>/dev/null"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "line1" ]
    [ "${lines[1]}" = "line2" ]
    [ "${lines[2]}" = "line3" ]
}

@test "zz-input with an empty literal argument falls back to stdin" {
    run bash -c 'echo "stdin-value" | zz-input ""'
    [ "$status" -eq 0 ]
    [ "$output" = "stdin-value" ]
}
