#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ORIG_HOME="$HOME"
    export HOME="$(mktemp -d)"
    git config --global user.name "Global User"
    git config --global user.email "global@example.com"
    git config --global commit.gpgsign false
    git config --global init.defaultBranch main
    WORK=$(mktemp -d)
    cd "$WORK"
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$HOME"
    export HOME="$ORIG_HOME"
}

@test "git-fix-author is installed on PATH and syntactically valid" {
    command -v git-fix-author
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage and does not touch any config" {
    git init -q
    run git-fix-author -h
    [[ "$output" == *"Set user.name and user.email"* ]]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"git-fix-author"* ]]
}

@test "fails cleanly outside a git repository" {
    run git-fix-author deadbeef
    [[ "$output" == *"not a git repository"* ]]
}

@test "copies user.name/user.email from the given commit's author into local config" {
    git init -q
    git config commit.gpgsign false
    git config user.name Alice
    git config user.email alice@example.com
    echo a >f && git add f && git commit -qm c1
    git config user.name Bob
    git config user.email bob@example.com
    echo b >>f && git add f && git commit -qm c2
    sha1=$(git rev-parse HEAD~1)

    run git-fix-author "$sha1"
    [ "$(git config user.name)" = "Alice" ]
    [ "$(git config user.email)" = "alice@example.com" ]
}

@test "always removes the global user section, even before setting the local one" {
    git init -q
    git config commit.gpgsign false
    git config user.name Alice
    git config user.email alice@example.com
    echo a >f && git add f && git commit -qm c1
    sha0=$(git rev-parse HEAD)

    run git-fix-author "$sha0"
    run git config --global user.name
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "an invalid sha leaves existing local config untouched" {
    git init -q
    git config commit.gpgsign false
    git config user.name Alice
    git config user.email alice@example.com
    echo a >f && git add f && git commit -qm c1

    run git-fix-author deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    [ "$(git config user.name)" = "Alice" ]
    [ "$(git config user.email)" = "alice@example.com" ]
}
