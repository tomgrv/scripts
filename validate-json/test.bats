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

@test "validate-json is installed on PATH and syntactically valid" {
    command -v validate-json
    run bash -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "validate-json -h prints usage and exits non-zero" {
    run validate-json -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "validate-json fails with no arguments (missing json and schema)" {
    run validate-json
    [ "$status" -ne 0 ]
}

@test "validate-json accepts an object against the default fallback schema" {
    echo '{"name":"x"}' >x.json
    run validate-json -a -f local -l true x.json
    [ "$status" -eq 0 ]
}

@test "validate-json fails on a file that does not exist" {
    run validate-json -f local -l true does-not-exist.json
    [ "$status" -ne 0 ]
}

@test "validate-json fails with no schema resolvable" {
    echo '{"name":"x"}' >x.json
    run validate-json x.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema is missing"* || "$output" == *"missing"* ]]
}

@test "validate-json validates against an explicit schema file" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"],
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"name":"x"}' >x.json
    run validate-json -s schema.json x.json
    [ "$status" -eq 0 ]
}

@test "validate-json rejects a value violating a required property" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"],
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"other":1}' >x.json
    run validate-json -s schema.json x.json
    [ "$status" -ne 0 ]
}

@test "validate-json rejects a value with the wrong property type" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"name":123}' >x.json
    run validate-json -s schema.json x.json
    [ "$status" -ne 0 ]
}

@test "validate-json infers schema from a local folder based on file suffix" {
    mkdir -p schemas
    cat >schemas/_widget.schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"]
}
EOF
    echo '{"name":"x"}' >thing.widget.json
    run validate-json -l schemas thing.widget.json
    [ "$status" -eq 0 ]
}

@test "validate-json uses fallback schema when nothing else resolves" {
    echo '{"name":"x"}' >x.json
    run validate-json -f local -l true x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"fallback"* || "$output" == *"valid"* ]]
}

@test "validate-json rejects a malformed JSON file" {
    echo '{not valid json' >bad.json
    run validate-json -f local -l true bad.json
    [ "$status" -ne 0 ]
}
