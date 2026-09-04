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

@test "git-fix-del is installed on PATH and syntactically valid" {
    command -v git-fix-del
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-del -h prints usage and exits non-zero" {
    run git-fix-del -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Delete a specified commit"* ]]
}

@test "git-fix-del fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-del -a somesha </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-del refuses to delete the initial (parentless) commit" {
    echo one > f && git add f && git commit -qm "first"
    sha=$(git rev-parse HEAD)
    run git-fix-del -a "$sha" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot delete commit"* ]]
    [ "$(git log --oneline | wc -l)" -eq 1 ]
}

@test "git-fix-del fails on an invalid/unknown sha" {
    echo one > f && git add f && git commit -qm "first"
    run git-fix-del -a deadbeef </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-del removes a middle commit and rebases descendants (auto mode)" {
    echo one > f && git add f && git commit -qm "first"
    echo two >> f && git add f && git commit -qm "second"
    target=$(git rev-parse HEAD)
    echo three >> f && git add f && git commit -qm "third"

    run git-fix-del -a "$target" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"successfully deleted"* ]]

    # "second" should be gone, "first" and "third" remain
    run git log --format=%s
    [ "$status" -eq 0 ]
    [[ "$output" == *"first"* ]]
    [[ "$output" == *"third"* ]]
    [[ "$output" != *"second"* ]]
    [ "$(git log --oneline | wc -l)" -eq 2 ]

    # content reflects both surviving commits (one + three, not two)
    run cat f
    [[ "$output" == *"one"* ]]
    [[ "$output" == *"three"* ]]
}
