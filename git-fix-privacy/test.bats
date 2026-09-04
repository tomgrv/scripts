#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q -b main
    git config user.email old@example.com
    git config user.name "Old Name"
    git config commit.gpgsign false
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-fix-privacy is installed on PATH and syntactically valid" {
    command -v git-fix-privacy
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-privacy -h prints usage and exits non-zero" {
    run git-fix-privacy -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fix privacy in history"* ]]
}

@test "git-fix-privacy fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-privacy -o old@example.com -n new@example.com -a "New Name" </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-privacy rewrites author name/email across history and updates local git config" {
    echo one > f && git add f && git commit -qm "first"

    run git-fix-privacy -o old@example.com -n new@example.com -a "New Name" </dev/null
    [ "$status" -eq 0 ]

    [ "$(git log -1 --format='%an <%ae>')" = "New Name <new@example.com>" ]
    [ "$(git config user.email)" = "new@example.com" ]
    [ "$(git config user.name)" = "New Name" ]
}

@test "git-fix-privacy leaves commits by a different author untouched" {
    echo one > f && git add f && git commit -qm "first"
    git config user.email someoneelse@example.com
    git config user.name "Someone Else"
    echo two >> f && git add f && git commit -qm "second"

    run git-fix-privacy -o old@example.com -n new@example.com -a "New Name" </dev/null
    [ "$status" -eq 0 ]

    # first commit rewritten
    [ "$(git log --format='%ae' | tail -1)" = "new@example.com" ]
    # second commit (different author) untouched
    [ "$(git log --format='%ae' | head -1)" = "someoneelse@example.com" ]
}
