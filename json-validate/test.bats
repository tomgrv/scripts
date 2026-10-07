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

@test "json-validate is installed on PATH and syntactically valid" {
    command -v json-validate
    run bash -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "json-validate -h prints usage and exits non-zero" {
    run json-validate -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "json-validate fails with no arguments (missing json and schema)" {
    run json-validate
    [ "$status" -ne 0 ]
}

@test "json-validate accepts an object against the default fallback schema" {
    echo '{"name":"x"}' >x.json
    run json-validate -a -f local -l true x.json
    [ "$status" -eq 0 ]
}

@test "json-validate fails on a file that does not exist" {
    run json-validate -f local -l true does-not-exist.json
    [ "$status" -ne 0 ]
}

@test "json-validate fails with no schema resolvable" {
    echo '{"name":"x"}' >x.json
    run json-validate x.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema is missing"* || "$output" == *"missing"* ]]
}

@test "json-validate validates against an explicit schema file" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"],
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"name":"x"}' >x.json
    run json-validate -s schema.json x.json
    [ "$status" -eq 0 ]
}

@test "json-validate rejects a value violating a required property" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"],
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"other":1}' >x.json
    run json-validate -s schema.json x.json
    [ "$status" -ne 0 ]
}

@test "json-validate rejects a value with the wrong property type" {
    cat >schema.json <<'EOF'
{
    "type": "object",
    "properties": {"name": {"type": "string"}}
}
EOF
    echo '{"name":123}' >x.json
    run json-validate -s schema.json x.json
    [ "$status" -ne 0 ]
}

@test "json-validate infers schema from a local folder based on file suffix" {
    mkdir -p schemas
    cat >schemas/_widget.schema.json <<'EOF'
{
    "type": "object",
    "required": ["name"]
}
EOF
    echo '{"name":"x"}' >thing.widget.json
    run json-validate -l schemas thing.widget.json
    [ "$status" -eq 0 ]
}

@test "json-validate uses fallback schema when nothing else resolves" {
    echo '{"name":"x"}' >x.json
    run json-validate -f local -l true x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"fallback"* || "$output" == *"valid"* ]]
}

@test "json-validate rejects a malformed JSON file" {
    echo '{not valid json' >bad.json
    run json-validate -f local -l true bad.json
    [ "$status" -ne 0 ]
}
