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

@test "git-fix-mode is installed on PATH and syntactically valid" {
    command -v git-fix-mode
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-mode does nothing (exit 0) when there is no mode diff" {
    echo hi > f && git add f && git commit -qm "first"
    run git-fix-mode
    [ "$status" -eq 0 ]
    [ -z "$(git status --porcelain)" ]
}

@test "git-fix-mode reverts a tracked file's mode change back to what git recorded" {
    echo hi > script.sh
    chmod 644 script.sh
    git add script.sh && git commit -qm "add"

    chmod 755 script.sh
    [ -n "$(git diff -p -R --no-color)" ]

    run git-fix-mode
    [ "$status" -eq 0 ]

    mode=$(stat -c '%a' script.sh)
    [ "$mode" = "644" ]
    [ -z "$(git status --porcelain)" ]
}

@test "git-fix-mode leaves deleted files alone" {
    echo hi > script.sh
    chmod 644 script.sh
    git add script.sh && git commit -qm "add"

    rm script.sh
    run git-fix-mode
    [ "$status" -eq 0 ]
    [ ! -e script.sh ]
    run git status --porcelain
    [[ "$output" == *"D script.sh"* ]] || [[ "$output" == *" D script.sh"* ]]
}
