#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    export REPO_DIR="$BATS_TEST_TMPDIR/repo"
    export REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare "$REMOTE_DIR"
    git init -q "$REPO_DIR"
    cd "$REPO_DIR"
    git config user.email "test@example.com"
    git config user.name "Test"
    git remote add origin "$REMOTE_DIR"
    git commit -q --allow-empty -m "init"
    git push -q -u origin HEAD:main
}

teardown() {
    teardown_scripts_path
}

@test "bump-tag is on PATH and syntactically valid" {
    run bash -n "$(command -v bump-tag)"
    [ "$status" -eq 0 ]
}

@test "bump-tag creates an explicit tag, its dependent tags, and pushes them" {
    run bump-tag 1.2.3
    [ "$status" -eq 0 ]
    [ "$(git tag -l v1.2.3)" = "v1.2.3" ]
    [ "$(git tag -l v1.2)" = "v1.2" ]
    [ "$(git tag -l v1)" = "v1" ]
    run git ls-remote --tags origin
    [[ "$output" == *"refs/tags/v1.2.3"* ]]
}

@test "bump-tag reuses an already-existing tag instead of recreating it" {
    git tag v9.9.9
    run bump-tag 9.9.9
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
}
