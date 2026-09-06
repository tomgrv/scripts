#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    cd "$WORK"
    git init -q
    git config commit.gpgsign false
    git config user.name t
    git config user.email t@t.com
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK"
}

@test "git-fix is installed on PATH and syntactically valid" {
    command -v git-fix
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "no subcommand: exits non-zero and lists available utilities" {
    run git-fix
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided."* ]]
    [[ "$output" == *"git-fix-author"* ]]
    [[ "$output" == *"git-fix-blanks"* ]]
}

@test "unknown subcommand: warns and lists available utilities, without erroring the shell" {
    run git-fix bogus-subcommand
    [ "$status" -eq 0 ]
    [[ "$output" == *"No dispatch target found"* ]]
    [[ "$output" == *"git-fix-author"* ]]
}

@test "dispatches to git-fix-author with remaining args" {
    echo a >f && git add f && git commit -qm init
    sha=$(git rev-parse HEAD)
    run git-fix author "$sha"
    [[ "$output" == *"Dispatching to executable target:"* ]]
    [[ "$output" == *"git-fix-author"* ]]
}

@test "dispatches to git-fix-blanks (dry-run) with remaining args" {
    echo a >f && git add f && git commit -qm init
    run git-fix blanks -d
    [[ "$output" == *"Dispatching to executable target:"* ]]
    [[ "$output" == *"git-fix-blanks"* ]]
}
