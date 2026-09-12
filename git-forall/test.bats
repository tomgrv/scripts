#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
    git config commit.gpgsign false
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-forall is installed on PATH and syntactically valid" {
    command -v git-forall
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "runs command against every tracked and untracked (non-ignored) file" {
    echo hi >tracked.txt
    git add tracked.txt
    git commit -qm init
    echo hi >untracked.txt
    echo ignoreme >ignored.txt
    echo ignored.txt >.gitignore
    git add .gitignore
    git commit -qm gitignore

    run git-forall echo
    [ "$status" -eq 0 ]
    [[ "$output" == *"tracked.txt"* ]]
    [[ "$output" == *"untracked.txt"* ]]
    [[ "$output" != *"ignored.txt"* ]]
}

@test "invokes the given command once per file with the file as final argument" {
    echo a >one.txt
    echo b >two.txt
    git add one.txt two.txt
    git commit -qm init

    run git-forall wc -l
    [ "$status" -eq 0 ]
    # wc -l one.txt / wc -l two.txt each report 1 line
    [ "$(echo "$output" | grep -c '^1 ')" -eq 2 ]
}

@test "produces no output when there are no files" {
    run git-forall echo
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-forall echo
    [[ "$output" == *"not a git repository"* ]]
}
