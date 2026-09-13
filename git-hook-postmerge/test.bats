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
    echo '{"name":"a"}' >package-lock.json
    git add package-lock.json
    git commit -qm "init"
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-hook-postmerge is installed on PATH and syntactically valid" {
    command -v git-hook-postmerge
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-postmerge -h prints usage and exits non-zero" {
    run git-hook-postmerge -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"post-merge hook"* ]]
}

@test "git-hook-postmerge fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-postmerge 0 </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-postmerge does nothing when no lockfile changed" {
    run git-hook-postmerge 0 </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"changed"* ]]
}

@test "git-hook-postmerge keeps theirs and warns when package-lock.json changed" {
    git checkout -q -b other
    echo '{"name":"b"}' >package-lock.json
    git commit -qam "change lock on other"
    git checkout -q main
    echo '{"name":"c"}' >package-lock.json
    git commit -qam "change lock on main"
    git merge -q --no-ff -X theirs other -m merge || true

    run git-hook-postmerge 0 </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"changed"* ]]
}
