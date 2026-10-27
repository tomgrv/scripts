#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    STEP="$BATS_TEST_TMPDIR/run.sh"
    printf 'up() { echo UP; }\ndown() { echo DOWN; }\n%s\n. zz-step\n' "${SUMMARY:-}" >"$STEP"
}

teardown() {
    teardown_scripts_path
}

@test "zz-step is installed on PATH and syntactically valid" {
    command -v zz-step
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "calls up() and down()" {
    run sh "$STEP" up
    [ "$output" = "UP" ]
    run sh "$STEP" down
    [ "$output" = "DOWN" ]
}

@test "summary is optional" {
    run sh "$STEP" summary
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "calls summary() when defined" {
    printf 'summary() { echo SUM; }\n. zz-step\n' >"$STEP.2"
    printf 'up() { :; }\nsummary() { echo SUM; }\n. zz-step\n' >"$STEP"
    run sh "$STEP" summary
    [ "$output" = "SUM" ]
}

@test "anything else is a usage error" {
    run sh "$STEP" bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
