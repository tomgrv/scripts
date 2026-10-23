#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    # A step: up/down/summary functions, then `. zz-step`.
    cat >"$WORK/run.sh" <<'STEP'
#!/bin/sh
up() { echo ran-up; }
down() { echo ran-down; }
summary() { echo ran-summary; }
. zz-step
STEP
    echo '{"name":"@x/step"}' >"$WORK/package.json"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-step is installed on PATH and syntactically valid" {
    command -v zz-step
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "zz-step runs up() by default and by name, down() and summary()" {
    run sh "$WORK/run.sh"
    [ "$output" = "ran-up" ]
    run sh "$WORK/run.sh" down
    [ "$output" = "ran-down" ]
    run sh "$WORK/run.sh" summary
    [ "$output" = "ran-summary" ]
}

@test "zz-step errors on down without down(), and prints nothing for summary without summary()" {
    printf '#!/bin/sh\nup() { echo ran-up; }\n. zz-step\n' >"$WORK/run.sh"
    run sh "$WORK/run.sh" down
    [ "$status" -eq 1 ]
    [[ "$output" == *"no 'down' action"* ]]
    run sh "$WORK/run.sh" summary
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "zz-step rejects an unknown action" {
    run sh "$WORK/run.sh" explode
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown action 'explode'"* ]]
}

@test "zz-step enforces config.requires for up and down, not for summary" {
    echo '{"name":"@x/step","config":{"requires":{"os":"notanos"}}}' >"$WORK/package.json"
    run sh "$WORK/run.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"targets notanos only"* ]]
    run sh "$WORK/run.sh" down
    [ "$status" -eq 1 ]
    run sh "$WORK/run.sh" summary
    [ "$status" -eq 0 ]
    [ "$output" = "ran-summary" ]
}
