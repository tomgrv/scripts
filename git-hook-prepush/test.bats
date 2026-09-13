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
    stub_script validate-branch-name <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    # zz_npx looks in ./node_modules/.bin before falling back to npx, so a
    # PATH-level stub alone (needed for zz_use's own `command -v` check)
    # isn't enough to keep this hermetic — mirror it there too.
    mkdir -p node_modules/.bin
    cp "$TEST_BIN/validate-branch-name" node_modules/.bin/validate-branch-name
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-hook-prepush is installed on PATH and syntactically valid" {
    command -v git-hook-prepush
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-prepush -h prints usage and exits non-zero" {
    run git-hook-prepush -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"pre-push hook"* ]]
}

@test "git-hook-prepush fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-prepush origin git@example.com:x.git </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-prepush validates the branch name via validate-branch-name" {
    run git-hook-prepush origin git@example.com:x.git </dev/null
    [ "$status" -eq 0 ]
}

@test "git-hook-prepush fails when validate-branch-name rejects the branch" {
    stub_script validate-branch-name <<-'EOF'
	#!/bin/sh
	echo "invalid branch name" >&2
	exit 1
	EOF
    cp "$TEST_BIN/validate-branch-name" node_modules/.bin/validate-branch-name
    run git-hook-prepush origin git@example.com:x.git </dev/null
    [ "$status" -ne 0 ]
}
