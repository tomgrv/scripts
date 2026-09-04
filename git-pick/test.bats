#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
    git config commit.gpgsign false
    printf 'v1\n' >a.txt
    git add a.txt
    git commit -qm c1
    C1=$(git rev-parse HEAD)
    printf 'v2\n' >a.txt
    git add a.txt
    git commit -qm c2
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-pick is installed on PATH and syntactically valid" {
    command -v git-pick
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "--help prints usage and exits non-zero" {
    run git-pick -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Pick files from a specific commit"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "restores current directory content from the given commit into the worktree and index" {
    run git-pick -c "$C1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully picked files from commit $C1"* ]]
    [ "$(cat a.txt)" = "v1" ]
    [ "$(git status --porcelain a.txt)" = "M  a.txt" ]
}

@test "restores only the given path when one is provided" {
    printf 'other\n' >b.txt
    git add b.txt
    git commit -qm c3

    run git-pick -c "$C1" a.txt
    [ "$status" -eq 0 ]
    [ "$(cat a.txt)" = "v1" ]
    [ -f b.txt ]
    [ "$(git status --porcelain)" = "M  a.txt" ]
}

@test "defaults the path to the current directory relative to repo root" {
    mkdir sub
    printf 'nested\n' >sub/n.txt
    git add sub/n.txt
    git commit -qm c3
    printf 'changed\n' >sub/n.txt
    cd sub

    run git-pick -c "$C1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Target path: sub"* || "$output" == *"Target path: ."* ]]
}

@test "fails cleanly when given an invalid commit" {
    run git-pick -c deadbeef
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to pick files from commit deadbeef"* ]]
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-pick -c HEAD
    [ "$status" -ne 0 ]
}
