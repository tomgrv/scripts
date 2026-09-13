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
    echo '{}' >package.json
    stub_script commitlint <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    stub_script devmoji <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    # zz_npx looks in ./node_modules/.bin before falling back to npx, so a
    # PATH-level stub alone (needed for zz_use's own `command -v` check)
    # isn't enough to keep this hermetic — mirror it there too.
    mkdir -p node_modules/.bin
    cp "$TEST_BIN/commitlint" node_modules/.bin/commitlint
    cp "$TEST_BIN/devmoji" node_modules/.bin/devmoji
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
    rm -f "$BATS_TEST_DIRNAME/../git-hook-installplugins/PLUGINS"
}

@test "git-hook-commitmsg is installed on PATH and syntactically valid" {
    command -v git-hook-commitmsg
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-commitmsg -h prints usage and exits non-zero" {
    run git-hook-commitmsg -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"commit-msg hook"* ]]
}

@test "git-hook-commitmsg fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-commitmsg msgfile </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-commitmsg errors when no message file is given" {
    run git-hook-commitmsg </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"No commit message file provided"* ]]
}

@test "git-hook-commitmsg runs commitlint and devmoji against a message file" {
    echo "feat: something" >msg.txt
    run git-hook-commitmsg msg.txt </dev/null
    [ "$status" -eq 0 ]
}
