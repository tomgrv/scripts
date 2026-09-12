#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ORIG_HOME="$HOME"
    export HOME="$(mktemp -d)"
    git config --global user.name t
    git config --global user.email t@t.com
    git config --global commit.gpgsign false
    git config --global init.defaultBranch main
    WORK=$(mktemp -d)
    cd "$WORK"
    git init -q
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$HOME"
    export HOME="$ORIG_HOME"
}

@test "git-co is installed on PATH and syntactically valid" {
    command -v git-co
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    run git-co -h
    [[ "$output" == *"git enhanced commit"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "missing commit message is required and exits non-zero" {
    echo a >f && git add f
    run git-co
    [ "$status" -eq 1 ]
    [[ "$output" == *"Commit message is required"* ]]
    # nothing got committed
    run git log --oneline
    [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "plain commit leaves message unmodified when no gitflow feature prefix is configured" {
    echo a >f && git add f
    run git-co "feat: add thing"
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "feat: add thing" ]
}

@test "-s injects the given scope into a conventional-commit message" {
    echo a >f && git add f
    run git-co -s api "feat: add thing"
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "feat(api):  add thing" ]
}

@test "-n suppresses scope injection" {
    echo a >f && git add f
    run git-co -n "feat: add thing"
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "feat: add thing" ]
}

@test "message with an existing scope is left untouched" {
    echo a >f && git add f
    run git-co "fix(api): thing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Scope already set in commit message"* ]]
    [ "$(git log -1 --format=%s)" = "fix(api): thing" ]
}

@test "uses gitflow feature-branch prefix to derive the scope" {
    echo base >base.txt && git add base.txt && git commit -qm base
    git config gitflow.prefix.feature "feature/"
    git checkout -qb feature/login
    echo a >f && git add f
    run git-co "feat: add login flow"
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "feat(login):  add login flow" ]
}

@test "outside a git repository, the underlying git commit fails (nothing committed)" {
    cd "$(mktemp -d)"
    run git-co "feat: msg"
    [[ "$output" == *"not a git repository"* ]]
    run git log
    [ "$status" -ne 0 ]
}
