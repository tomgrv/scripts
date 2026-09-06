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

@test "git-fix-lock is installed on PATH and syntactically valid" {
    command -v git-fix-lock
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-lock -h prints usage and exits non-zero" {
    run git-fix-lock -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Fix git lock files"* ]]
}

@test "git-fix-lock is a harmless no-op outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-lock </dev/null
    # no repo => no conflicted files found => nothing done, no crash/hang
    [ "$status" -eq 0 ]
}

@test "git-fix-lock does nothing when there are no lock-file conflicts" {
    echo hi > f && git add f && git commit -qm "first"
    run git-fix-lock </dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git-fix-lock resolves a package-lock.json conflict by keeping ours and regenerating" {
    echo '{"name":"t","version":"1.0.0"}' > package.json
    echo '{"name":"t","version":"1.0.0","lockfileVersion":3,"note":"base"}' > package-lock.json
    git add -A && git commit -qm base

    git checkout -qb feature
    echo '{"name":"t","version":"1.0.0","lockfileVersion":3,"note":"feature"}' > package-lock.json
    git add -A && git commit -qm feature

    git checkout -q main
    echo '{"name":"t","version":"1.0.0","lockfileVersion":3,"note":"ours"}' > package-lock.json
    git add -A && git commit -qm mainchange

    git merge feature -q || true
    run git status --porcelain
    [[ "$output" == *"UU package-lock.json"* ]]

    run git-fix-lock </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fixing merge conflict in package-lock.json"* ]]
    [[ "$output" == *"Regenerating package-lock.json"* ]]

    # conflict resolved, file staged, content reflects "ours" (kept before regen)
    run git status --porcelain
    [[ "$output" == *"package-lock.json"* ]]
    [[ "$output" != *"UU"* ]]
    grep -q '"note": *"ours"' package-lock.json
    ! grep -q '<<<<<<<' package-lock.json
}
