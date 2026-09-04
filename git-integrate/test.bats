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
    printf 'hello\n' >a.txt
    git add a.txt
    git commit -qm init
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-integrate is installed on PATH and syntactically valid" {
    command -v git-integrate
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "sets core.autocrlf to false" {
    git config core.autocrlf true
    run git-integrate
    [ "$status" -eq 0 ]
    [ "$(git config core.autocrlf)" = "false" ]
}

@test "reverts a modified file whose only diff is whitespace/CRLF" {
    printf 'hello\r\n' >a.txt
    run git-integrate
    [ "$status" -eq 0 ]
    [ -z "$(git status --porcelain)" ]
    [ "$(git diff --stat)" = "" ]
}

@test "stages a modified file with real content changes" {
    printf 'goodbye\n' >a.txt
    run git-integrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"File changed: a.txt"* ]]
    [ "$(git status --porcelain a.txt)" = "M  a.txt" ]
}

@test "stages a new untracked file" {
    printf 'new\n' >b.txt
    run git-integrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Add new file: b.txt"* ]]
    [ "$(git status --porcelain b.txt)" = "A  b.txt" ]
}

@test "leaves a clean working tree untouched" {
    run git-integrate
    [ "$status" -eq 0 ]
    [ -z "$(git status --porcelain)" ]
}

@test "does not crash outside a git repository" {
    cd /
    run git-integrate
    [[ "$output" == *"not a git repository"* ]]
}
