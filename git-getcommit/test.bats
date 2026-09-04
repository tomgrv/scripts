#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo a >a.txt
    git add a.txt
    git commit -q -m "first"
    FIRST_SHA=$(git rev-parse HEAD)
    echo b >b.txt
    git add b.txt
    git commit -q -m "second"
    SECOND_SHA=$(git rev-parse HEAD)
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "git-getcommit is installed on PATH and syntactically valid" {
    command -v git-getcommit
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-getcommit -h prints usage and exits non-zero" {
    run git-getcommit -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "git-getcommit prints the resolved full sha for a given commit" {
    run git-getcommit "$SECOND_SHA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SECOND_SHA"* ]]
}

@test "git-getcommit resolves an abbreviated sha to the full sha" {
    short=$(git rev-parse --short "$SECOND_SHA")
    run git-getcommit "$short"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SECOND_SHA"* ]]
}

@test "git-getcommit treats sha '0' as the very first commit in history" {
    run git-getcommit 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"$FIRST_SHA"* ]]
}

@test "git-getcommit -p prints the parent of the given commit" {
    run git-getcommit -p "$SECOND_SHA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$FIRST_SHA"* ]]
}

@test "git-getcommit prints nothing (but does not crash) for an unresolvable sha" {
    run git-getcommit doesnotexistsha
    [[ "$output" != *"$SECOND_SHA"* ]]
    [[ "$output" != *"$FIRST_SHA"* ]]
}
