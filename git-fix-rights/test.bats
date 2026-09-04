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

@test "git-fix-rights is installed on PATH and syntactically valid" {
    command -v git-fix-rights
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-rights -h prints usage and exits non-zero" {
    run git-fix-rights -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fix git access rights"* ]]
}

@test "git-fix-rights is a harmless no-op outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-rights </dev/null
    # no repo => no tracked files => nothing to chmod, no crash/hang
    [ "$status" -eq 0 ]
}

@test "git-fix-rights normalizes permissions for tracked files and directories" {
    echo hi > readme.txt && chmod 600 readme.txt
    printf '#!/bin/sh\necho hi\n' > script.sh && chmod 600 script.sh
    echo SECRET=1 > secrets.env && chmod 644 secrets.env
    mkdir -p logs && echo l > logs/a.log && chmod 755 logs
    git add -A && git commit -qm "add"

    run git-fix-rights
    [ "$status" -eq 0 ]
    [[ "$output" == *"Access rights have been set"* ]]

    [ "$(stat -c '%a' readme.txt)" = "644" ]
    [ "$(stat -c '%a' script.sh)" = "755" ]
    [ "$(stat -c '%a' secrets.env)" = "600" ]
    [ "$(stat -c '%a' logs)" = "700" ]
}

@test "git-fix-rights leaves untracked files alone" {
    echo hi > tracked.txt && chmod 600 tracked.txt
    git add tracked.txt && git commit -qm "add"
    echo hi > untracked.txt && chmod 600 untracked.txt

    run git-fix-rights
    [ "$status" -eq 0 ]

    [ "$(stat -c '%a' tracked.txt)" = "644" ]
    [ "$(stat -c '%a' untracked.txt)" = "600" ]
}
