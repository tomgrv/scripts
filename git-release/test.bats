#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "git-release is installed on PATH and syntactically valid" {
    command -v git-release
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails with no subcommand" {
    run git-release
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided"* ]]
}

@test "reports no dispatch target for an unknown subcommand" {
    run git-release bogus-subcommand-xyz
    [[ "$output" == *"No dispatch target found"* ]]
}

@test "dispatches to git-release-alpha and forwards its arguments" {
    run git-release alpha -h
    [[ "$output" == *"Dispatching to executable target"* ]]
    [[ "$output" == *"Release squashed current branch to develop branch"* ]]
}

@test "dispatches to git-release-beta" {
    run git-release beta -h
    [[ "$output" == *"Dispatching to executable target"* ]]
    [[ "$output" == *"git-release-beta"* ]]
}

@test "dispatches to git-release-hotfix and forwards its arguments" {
    run git-release hotfix -h
    [[ "$output" == *"Dispatching to executable target"* ]]
    [[ "$output" == *"Create HotFix branch"* ]]
}

@test "dispatches to git-release-prod" {
    run git-release prod -h
    [[ "$output" == *"Dispatching to executable target"* ]]
    [[ "$output" == *"Release production branch"* ]]
}

@test "lists available utilities when no subcommand matches" {
    run git-release
    [[ "$output" == *"git-release-alpha"* ]]
    [[ "$output" == *"git-release-beta"* ]]
    [[ "$output" == *"git-release-hotfix"* ]]
    [[ "$output" == *"git-release-prod"* ]]
}
