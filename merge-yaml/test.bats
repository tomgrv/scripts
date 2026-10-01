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

@test "merge-yaml is installed on PATH and syntactically valid" {
    command -v merge-yaml
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "merge-yaml -h prints usage and exits non-zero" {
    run merge-yaml -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "merge-yaml errors with no arguments" {
    run merge-yaml
    [ "$status" -ne 0 ]
}

@test "merge-yaml errors with only a target argument" {
    printf 'a: 1\n' >target.yaml
    run merge-yaml target.yaml
    [ "$status" -ne 0 ]
}

@test "merge-yaml errors when target file does not exist" {
    printf 'a: 1\n' >source.yaml
    run merge-yaml does-not-exist.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "merge-yaml errors when target file is not valid YAML" {
    printf ':\n  - broken: [\n' >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid YAML"* ]]
}

@test "merge-yaml errors clearly when yq is not mikefarah/yq" {
    stub_script yq <<'EOF2'
#!/bin/sh
echo "yq 3.4.3"
EOF2
    printf 'a: 1\n' >target.yaml
    printf 'b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires mikefarah/yq"* ]]
}

@test "merge-yaml keeps a GitHub workflow 'on' key unquoted" {
    printf 'on:\n  push: {}\n' >target.yaml
    printf 'on:\n  pull_request: {}\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    run cat target.yaml
    [[ "$output" == *"on:"* ]]
    [[ "$output" != *"'on'"* ]]
    [[ "$output" != *"true:"* ]]
    [[ "$output" == *"pull_request"* ]]
}

@test "merge-yaml reports the yq parse error for invalid YAML" {
    printf ':\n  - broken: [\n' >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid YAML: "?* ]]
}

@test "merge-yaml merges a source object into the target file in place" {
    printf 'a: 1\n' >target.yaml
    printf 'b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    run cat target.yaml
    [[ "$output" == *"a: 1"* ]]
    [[ "$output" == *"b: 2"* ]]
}

@test "merge-yaml merges from stdin when source is -" {
    printf 'a: 1\n' >target.yaml
    run bash -c "printf 'b: 2\n' | merge-yaml target.yaml -"
    [ "$status" -eq 0 ]
    run cat target.yaml
    [[ "$output" == *"a: 1"* ]]
    [[ "$output" == *"b: 2"* ]]
}

@test "merge-yaml unions and dedupes array values" {
    printf 'list:\n  - 1\n  - 2\n  - 3\n' >target.yaml
    printf 'list:\n  - 2\n  - 3\n  - 4\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    result=$(cat target.yaml)
    count=$(echo "$result" | grep -c '^\s*- 2\s*$')
    [ "$count" -eq 1 ]
    [[ "$result" == *"- 4"* ]]
}

@test "merge-yaml reconciles array objects by id" {
    printf 'l:\n  - id: 1\n    v: a\n  - id: 2\n    v: b\n' >target.yaml
    printf 'l:\n  - id: 2\n    v: z\n    w: c\n  - id: 3\n    v: d\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json -I0 . target.yaml)" = '{"l":[{"id":1,"v":"a"},{"id":2,"v":"b","w":"c"},{"id":3,"v":"d"}]}' ]
}

@test "merge-yaml reconciles array objects by name when no id" {
    printf 'l:\n  - name: x\n    v: 1\n' >target.yaml
    printf 'l:\n  - name: x\n    w: 2\n  - name: y\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json -I0 . target.yaml)" = '{"l":[{"name":"x","v":1,"w":2},{"name":"y"}]}' ]
}

@test "merge-yaml dedupes array objects without id or name by equality" {
    printf 'l:\n  - {a: 1}\n' >target.yaml
    printf 'l:\n  - {a: 1}\n  - {a: 2}\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json -I0 . target.yaml)" = '{"l":[{"a":1},{"a":2}]}' ]
}

@test "merge-yaml recursively merges nested objects" {
    printf 'nested:\n  a: 1\n' >target.yaml
    printf 'nested:\n  b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    result=$(cat target.yaml)
    [[ "$result" == *"a: 1"* ]]
    [[ "$result" == *"b: 2"* ]]
}

@test "merge-yaml keeps the target's comments, key order and flow style" {
    printf '# header\nz: 1 # keep\nlist: [1, 2]\na: {x: 1}\n' >target.yaml
    printf 'b: 2\nlist: [2, 3]\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    run cat target.yaml
    [ "${lines[0]}" = "# header" ]
    [ "${lines[1]}" = "z: 1 # keep" ]
    [ "${lines[2]}" = "list: [1, 2, 3]" ]
    [ "${lines[3]}" = "a: {x: 1}" ]
    [ "${lines[4]}" = "b: 2" ]
}

@test "merge-yaml keeps target values on conflicts" {
    printf 'a: 1\nm: {k: 1}\nl: [1]\n' >target.yaml
    printf 'a: 2\nm: 3\nl: x\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json -I0 . target.yaml)" = '{"a":1,"m":{"k":1},"l":[1]}' ]
}

@test "merge-yaml writes 2-space indents by default" {
    printf 'nested:\n  a: 1\n' >target.yaml
    printf 'nested:\n  b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    grep -qE '^  a: 1' target.yaml
}

@test "merge-yaml honours -i for the output indent" {
    printf 'nested:\n  a: 1\n' >target.yaml
    printf 'nested:\n  b: 2\n' >source.yaml
    run merge-yaml -i 4 target.yaml source.yaml
    [ "$status" -eq 0 ]
    grep -qE '^    a: 1' target.yaml
}

@test "merge-yaml fills an empty target from the source" {
    : >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(cat target.yaml)" = "a: 1" ]
}

@test "merge-yaml keeps an explicit null target" {
    printf 'null\n' >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json . target.yaml)" = "null" ]
}

@test "merge-yaml fills a comments-only target from the source" {
    printf '# only a comment\n\n' >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    [ "$(yq -o=json -I0 . target.yaml)" = '{"a":1}' ]
}

@test "merge-yaml writes intermediates to a private temp dir" {
    ! grep -q '/tmp/\$\$' "$BATS_TEST_DIRNAME/run.sh"
    grep -q 'mktemp -d' "$BATS_TEST_DIRNAME/run.sh"
}
