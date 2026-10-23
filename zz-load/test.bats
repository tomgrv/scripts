#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-load is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-load)"
    [ "$status" -eq 0 ]
}

@test "zz-load reads a literal argument" {
    run zz-load "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "zz-load reads a file argument" {
    tmp=$(mktemp)
    echo "from-file" >"$tmp"
    run zz-load "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-file"* ]]
}

@test "zz-load reads stdin when no argument given" {
    run bash -c 'echo "from-stdin" | zz-load'
    [ "$status" -eq 0 ]
    [ "$output" = "from-stdin" ]
}

@test "zz-load treats a non-existent path as a literal string, not an error" {
    run zz-load "/no/such/file/here"
    [ "$status" -eq 0 ]
    [ "$output" = "/no/such/file/here" ]
}

@test "zz-load reading a file logs which file it read from, to stderr" {
    tmp=$(mktemp)
    echo "contents" >"$tmp"
    run bash -c "zz-load '$tmp' 2>&1 1>/dev/null"
    rm -f "$tmp"
    [[ "$output" == *"$tmp"* ]]
}

@test "zz-load preserves multi-line file content" {
    tmp=$(mktemp)
    printf 'line1\nline2\nline3\n' >"$tmp"
    run bash -c "zz-load '$tmp' 2>/dev/null"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "line1" ]
    [ "${lines[1]}" = "line2" ]
    [ "${lines[2]}" = "line3" ]
}

@test "zz-load with an empty literal argument falls back to stdin" {
    run bash -c 'echo "stdin-value" | zz-load ""'
    [ "$status" -eq 0 ]
    [ "$output" = "stdin-value" ]
}
