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

@test "git-fix-message is installed on PATH and syntactically valid" {
    command -v git-fix-message
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-message -h prints usage and exits non-zero" {
    run git-fix-message -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Rewrite an arbitrary commit message"* ]]
}

@test "git-fix-message fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-message -m "x" HEAD </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-message refuses to run with uncommitted changes" {
    echo one > f && git add f && git commit -qm "first"
    echo dirty >> f
    run git-fix-message -m "new" HEAD </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "git-fix-message rejects an invalid commit sha" {
    echo one > f && git add f && git commit -qm "first"
    run git-fix-message -m "new" deadbeef </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid commit"* ]]
}

@test "git-fix-message errors when the given commit is not an ancestor of HEAD" {
    echo one > f && git add f && git commit -qm "first"
    git checkout -qb other
    echo two >> f && git add f && git commit -qm "other-branch-commit"
    other_sha=$(git rev-parse HEAD)
    git checkout -q main

    run git-fix-message -m "new" "$other_sha" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"not in the current branch history"* ]]
}

@test "git-fix-message rewrites the message of an arbitrary (non-HEAD) commit" {
    echo one > f && git add f && git commit -qm "first"
    echo two >> f && git add f && git commit -qm "second"
    target=$(git rev-parse HEAD)
    echo three >> f && git add f && git commit -qm "third"

    run bash -c 'echo y | git-fix-message -m "reworded second" '"$target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commit message rewritten successfully"* ]]

    run git log --format=%s
    [[ "$output" == *"reworded second"* ]]
    [[ "$output" == *"first"* ]]
    [[ "$output" == *"third"* ]]
    [[ "$output" != *$'\n'"second"$'\n'* ]]

    # history length and file content preserved
    [ "$(git log --oneline | wc -l)" -eq 3 ]
    [ "$(cat f)" = "$(printf 'one\ntwo\nthree')" ]
}

@test "git-fix-message aborts when the user declines the confirmation prompt" {
    echo one > f && git add f && git commit -qm "first"
    orig=$(git log -1 --format=%s)

    run bash -c 'echo n | git-fix-message -m "should not apply" HEAD'
    [ "$status" -ne 0 ]
    [[ "$output" == *"cancelled by user"* ]]
    [ "$(git log -1 --format=%s)" = "$orig" ]
}
