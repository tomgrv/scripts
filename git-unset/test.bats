#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-unset is installed on PATH and syntactically valid" {
    command -v git-unset
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "unsets all local keys matching the given prefix, leaving others intact" {
    git config foo.bar baz
    git config foo.qux quux
    git config other.key val

    run git-unset foo
    [ "$status" -eq 0 ]
    [ -z "$(git config --local --get-regexp '^foo\.')" ]
    [ "$(git config --local --get other.key)" = "val" ]
}

@test "is a no-op when nothing matches the prefix" {
    git config other.key val
    run git-unset nomatchingprefix
    [ "$status" -eq 0 ]
    [ "$(git config --local --get other.key)" = "val" ]
}

@test "defaults to matching any lower-case prefix when none is given" {
    git config foo.bar baz
    git config other.key val

    run git-unset
    [ "$status" -eq 0 ]
    [ -z "$(git config --local -l)" ]
}

@test "operates on a different scope when given as second argument" {
    HOME_DIR=$(mktemp -d)
    HOME="$HOME_DIR" git config --global test.thing1 a
    HOME="$HOME_DIR" git config --global test.thing2 b

    HOME="$HOME_DIR" run git-unset test --global
    [ "$status" -eq 0 ]
    [ -z "$(HOME="$HOME_DIR" git config --global --get-regexp '^test\.')" ]
    rm -rf "$HOME_DIR"
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-unset foo
    [[ "$output" == *"not a git repository"* ]]
}
