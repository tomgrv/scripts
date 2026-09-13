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
    mkdir -p .git
    echo '{}' >package.json
    stub_script git-cz <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    # zz_npx looks in ./node_modules/.bin before falling back to npx, so a
    # PATH-level stub alone (needed for zz_use's own `command -v` check)
    # isn't enough to keep this hermetic — mirror it there too.
    mkdir -p node_modules/.bin
    cp "$TEST_BIN/git-cz" node_modules/.bin/git-cz
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
    rm -f "$BATS_TEST_DIRNAME/../git-hook-installplugins/PLUGINS"
}

@test "git-hook-preparecommitmsg is installed on PATH and syntactically valid" {
    command -v git-hook-preparecommitmsg
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-preparecommitmsg -h prints usage and exits non-zero" {
    run git-hook-preparecommitmsg -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"prepare-commit-msg hook"* ]]
}

@test "git-hook-preparecommitmsg fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-preparecommitmsg msgfile </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-preparecommitmsg skips commitizen when a message is already present" {
    printf 'feat: something\n' >.git/COMMIT_EDITMSG
    run git-hook-preparecommitmsg .git/COMMIT_EDITMSG message </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commitizen not relevant"* ]]
}
