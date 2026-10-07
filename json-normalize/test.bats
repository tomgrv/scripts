#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "json-normalize is installed on PATH and syntactically valid" {
    command -v json-normalize
    run bash -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "json-normalize -h prints usage and exits non-zero" {
    run json-normalize -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "json-normalize sorts keys and prints the result to stdout" {
    echo '{"b":1,"a":2}' >x.json
    run json-normalize -c -a -i -t 2 -f local -l true x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a": 2'* ]]
    # not written in place without -w
    grep -q '"b":1' x.json
}

@test "json-normalize -w writes the normalized result back to the file" {
    echo '{"b":1,"a":2}' >x.json
    run json-normalize -w -a -f local -l true x.json
    [ "$status" -eq 0 ]
    run cat x.json
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "json-normalize fails and refuses -w when reading from stdin" {
    run bash -c 'echo "{\"a\":1}" | json-normalize -w -a -f local -l true'
    [ "$status" -ne 0 ]
    [[ "$output" == *"stdin"* ]]
}

@test "json-normalize reads from stdin when no files given and prints result" {
    run bash -c 'echo "{\"b\":1,\"a\":2}" | json-normalize -a -f local -l true'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a"'* ]]
}

@test "json-normalize reports but does not crash on a file that does not exist" {
    run json-normalize -a -f local -l true does-not-exist.json
    [[ "$output" == *"not found"* ]]
}

@test "json-normalize errors when the file does not validate against schema" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "required": ["must_have"]
}
EOF
    echo '{"a":1}' >x.json
    run json-normalize -s schema.json x.json
    [ "$status" -ne 0 ]
}

@test "json-normalize normalizes multiple files given as multiple arguments" {
    echo '{"b":1,"a":2}' >x.json
    echo '{"d":1,"c":2}' >y.json
    run json-normalize -a -f local -l true x.json y.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"c"'* ]]
}
