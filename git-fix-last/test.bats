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
    export GIT_EDITOR=true
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-fix-last is installed on PATH and syntactically valid" {
    command -v git-fix-last
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-last -h prints usage and exits non-zero" {
    run git-fix-last -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Edit the last commit"* ]]
}

@test "git-fix-last fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-last -m "x" </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-last rewrites the last commit's message with -m, without adding a commit" {
    echo one > f && git add f && git commit -qm "orig msg"
    parent_count_before=$(git log --oneline | wc -l)

    run git-fix-last -m "amended msg" </dev/null
    [ "$status" -eq 0 ]

    [ "$(git log -1 --format=%s)" = "amended msg" ]
    [ "$(git log --oneline | wc -l)" -eq "$parent_count_before" ]
}

@test "git-fix-last keeps commit content intact when only the message changes" {
    echo one > f && git add f && git commit -qm "orig msg"
    before_tree=$(git rev-parse HEAD^{tree})

    run git-fix-last -m "new message here" </dev/null
    [ "$status" -eq 0 ]

    [ "$(git rev-parse HEAD^{tree})" = "$before_tree" ]
    [ "$(cat f)" = "one" ]
}
