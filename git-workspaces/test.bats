#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "git-workspaces is installed on PATH and syntactically valid" {
    command -v git-workspaces
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-workspaces -h prints usage and exits non-zero" {
    run git-workspaces -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "git-workspaces falls back to listing all top-level directories with no package.json" {
    mkdir -p dir1 dir2
    touch file.txt
    run git-workspaces
    [ "$status" -eq 0 ]
    [[ "$output" == *"./dir1"* ]]
    [[ "$output" == *"./dir2"* ]]
}

@test "git-workspaces lists directories matching package.json workspaces globs" {
    mkdir -p packages/a packages/b other
    touch packages/a/f packages/b/f other/f
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    run git-workspaces
    [ "$status" -eq 0 ]
    [[ "$output" == *"packages/a"* ]]
    [[ "$output" == *"packages/b"* ]]
    [[ "$output" != *"./other"* ]]
}

@test "git-workspaces lists a literal (non-glob) workspace entry" {
    mkdir -p libs/core
    cat >package.json <<'EOF'
{"workspaces": ["libs/core"]}
EOF
    run git-workspaces
    [ "$status" -eq 0 ]
    [[ "$output" == *"libs/core"* ]]
}

@test "git-workspaces -r reports only workspaces touched within a commit range" {
    mkdir -p packages/a packages/b
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    touch packages/a/f packages/b/f
    git add -A
    git commit -q -m "initial"

    echo changed >packages/a/f
    git add -A
    git commit -q -m "touch a"

    run git-workspaces -r HEAD~1..HEAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"packages/a"* ]]
    [[ "$output" != *"packages/b"* ]]
}

@test "git-workspaces -r prints nothing when the range touches no workspace" {
    mkdir -p packages/a
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    touch packages/a/f
    git add -A
    git commit -q -m "initial"
    git commit -q --allow-empty -m "empty change"

    run git-workspaces -r HEAD~1..HEAD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
