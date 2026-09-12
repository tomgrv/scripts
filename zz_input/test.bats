#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_input is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_input)"
    [ "$status" -eq 0 ]
}

@test "zz_input reads a literal argument" {
    run zz_input "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "zz_input reads a file argument" {
    tmp=$(mktemp)
    echo "from-file" >"$tmp"
    run zz_input "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-file"* ]]
}

@test "zz_input reads stdin when no argument given" {
    run bash -c 'echo "from-stdin" | zz_input'
    [ "$status" -eq 0 ]
    [ "$output" = "from-stdin" ]
}

@test "zz_input treats a non-existent path as a literal string, not an error" {
    run zz_input "/no/such/file/here"
    [ "$status" -eq 0 ]
    [ "$output" = "/no/such/file/here" ]
}

@test "zz_input reading a file logs which file it read from, to stderr" {
    tmp=$(mktemp)
    echo "contents" >"$tmp"
    run bash -c "zz_input '$tmp' 2>&1 1>/dev/null"
    rm -f "$tmp"
    [[ "$output" == *"$tmp"* ]]
}

@test "zz_input preserves multi-line file content" {
    tmp=$(mktemp)
    printf 'line1\nline2\nline3\n' >"$tmp"
    run bash -c "zz_input '$tmp' 2>/dev/null"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "line1" ]
    [ "${lines[1]}" = "line2" ]
    [ "${lines[2]}" = "line3" ]
}

@test "zz_input with an empty literal argument falls back to stdin" {
    run bash -c 'echo "stdin-value" | zz_input ""'
    [ "$status" -eq 0 ]
    [ "$output" = "stdin-value" ]
}
