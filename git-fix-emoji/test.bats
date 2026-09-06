#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q -b main
    git config user.email a@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-fix-emoji is installed on PATH and syntactically valid" {
    command -v git-fix-emoji
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-emoji -h prints usage and exits non-zero" {
    run git-fix-emoji -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fix git emoji"* ]]
}

@test "git-fix-emoji fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-emoji </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-emoji refuses to run with uncommitted changes" {
    echo one > f && git add f && git commit -qm "first"
    echo dirty >> f
    run git-fix-emoji </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    # working tree must not have been touched further
    run git status --porcelain
    [ "$output" = " M f" ]
}
