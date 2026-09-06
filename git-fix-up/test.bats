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
    export GIT_SEQUENCE_EDITOR=true
    export GIT_EDITOR=true
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-fix-up is installed on PATH and syntactically valid" {
    command -v git-fix-up
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-up -h prints usage and exits non-zero" {
    run git-fix-up -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fix git history"* ]]
}

@test "git-fix-up refuses when a lock file is staged" {
    echo one > f && git add f && git commit -qm "first"
    echo '{}' > package-lock.json
    git add package-lock.json

    run git-fix-up
    [ "$status" -ne 0 ]
    [[ "$output" == *"Packages lock file are staged"* ]]
}

@test "git-fix-up refuses when nothing is staged" {
    echo one > f && git add f && git commit -qm "first"

    run git-fix-up
    [ "$status" -ne 0 ]
    [[ "$output" == *"No files are staged"* ]]
}

@test "git-fix-up creates a fixup commit for the target and autosquashes it in" {
    echo one > f && git add f && git commit -qm "first"
    echo two >> f && git add f && git commit -qm "second"
    target=$(git rev-parse HEAD)

    echo extra > g
    git add g

    run timeout 20 git-fix-up "$target"
    [ "$status" -eq 0 ]

    # no fixup commit left dangling, history squashed back into 2 commits
    [ "$(git log --oneline | wc -l)" -eq 2 ]
    run git log --format=%s
    [[ "$output" != *"fixup!"* ]]

    # content of the fixup was folded into the "second" commit
    run git show --stat HEAD
    [[ "$output" == *"g"* ]]
    [ "$(cat g)" = "extra" ]
    [ -z "$(git status --porcelain)" ]
}
