#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ORIGIN=$(mktemp -d)
    git init -q -b main --bare "$ORIGIN"
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q -b main
    git config user.email a@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    git remote add origin "$ORIGIN"
    echo one > f && git add f && git commit -qm "first"
    git push -q origin main
}

teardown() {
    cd /
    rm -rf "$REPO" "$ORIGIN"
    teardown_scripts_path
}

@test "git-fix-prune is installed on PATH and syntactically valid" {
    command -v git-fix-prune
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-prune -h prints usage and exits non-zero" {
    run git-fix-prune -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Prune remote-tracking references"* ]]
}

@test "git-fix-prune is a harmless no-op outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-prune </dev/null
    # no repo => no remotes found => nothing to prune, no crash/hang
    [ "$status" -eq 0 ]
}

@test "git-fix-prune removes stale remote-tracking refs for a branch deleted on the remote" {
    git checkout -qb feature
    git push -q origin feature
    git checkout -q main

    # simulate the branch having been deleted directly on the remote
    git -C "$ORIGIN" branch -D feature

    run git branch -r
    [[ "$output" == *"origin/feature"* ]]

    run git-fix-prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"pruned"* ]]

    run git branch -r
    [[ "$output" != *"origin/feature"* ]]
    [[ "$output" == *"origin/main"* ]]
}

@test "git-fix-prune accepts an explicit remote name" {
    git checkout -qb feature2
    git push -q origin feature2
    git checkout -q main
    git -C "$ORIGIN" branch -D feature2

    run git-fix-prune origin
    [ "$status" -eq 0 ]
    run git branch -r
    [[ "$output" != *"origin/feature2"* ]]
}
