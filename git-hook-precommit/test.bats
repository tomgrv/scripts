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
    echo '{"name":"tmp"}' >package.json
    git add package.json
    git commit -qm "init"

    stub_script git-precommit-checks <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    stub_script lint-staged <<-'EOF'
	#!/bin/sh
	exit 0
	EOF
    # zz_npx looks in ./node_modules/.bin before falling back to npx, so a
    # PATH-level stub alone (needed for zz_use's own `command -v` check)
    # isn't enough to keep this hermetic — mirror it there too.
    mkdir -p node_modules/.bin
    cp "$TEST_BIN/lint-staged" node_modules/.bin/lint-staged
    cp "$TEST_BIN/git-precommit-checks" node_modules/.bin/git-precommit-checks
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
    rm -f "$BATS_TEST_DIRNAME/../git-hook-installplugins/PLUGINS"
}

@test "git-hook-precommit is installed on PATH and syntactically valid" {
    command -v git-hook-precommit
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-precommit -h prints usage and exits non-zero" {
    run git-hook-precommit -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"pre-commit hook"* ]]
}

@test "git-hook-precommit fails cleanly outside a git repository" {
    OUTSIDE=$(mktemp -d)
    cd "$OUTSIDE"
    run git-hook-precommit </dev/null
    [ "$status" -ne 0 ]
    rm -rf "$OUTSIDE"
}

@test "git-hook-precommit skips during a rebase" {
    GIT_COMMAND=rebase run git-hook-precommit </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skip pre-commit hook during rebase"* ]]
}

@test "git-hook-precommit runs checks on a clean repo with no staged changes" {
    run git-hook-precommit </dev/null
    [ "$status" -eq 0 ]
}
