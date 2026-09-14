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
    echo one >f
    git add f
    git commit -qm "init"
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-hook-postcheckout is installed on PATH and syntactically valid" {
    command -v git-hook-postcheckout
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-postcheckout -h prints usage and exits non-zero" {
    run git-hook-postcheckout -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"post-checkout hook"* ]]
}

@test "git-hook-postcheckout fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-postcheckout HEAD HEAD 1 </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-postcheckout skips during a rebase" {
    GIT_COMMAND=rebase run git-hook-postcheckout HEAD HEAD 1 </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skip post-checkout hook during rebase"* ]]
}

@test "git-hook-postcheckout succeeds on a normal branch checkout" {
    run git-hook-postcheckout HEAD HEAD 1 </dev/null
    [ "$status" -eq 0 ]
}
