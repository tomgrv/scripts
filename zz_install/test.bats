#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    # STUBS holds the fake package managers plus just the tools run.sh
    # needs: exposing /usr/bin would surface the host's real managers.
    STUBS=$(mktemp -d)
    for tool in sh cat tr sed awk grep dirname readlink basename; do
        ln -s "$(command -v $tool)" "$STUBS/$tool"
    done
    export CALLS="$STUBS/calls"
    set_uid 0
}

teardown() {
    rm -rf "$STUBS"
    teardown_scripts_path
}

# Run zz_install seeing only the stubs (bats itself keeps the full PATH).
run_install() {
    PATH="$TEST_BIN:$STUBS" run command zz_install "$@"
}

# stub <name>: a manager that records its argv.
stub() {
    printf '#!/bin/sh\necho "%s $*" >> "$CALLS"\n' "$1" >"$STUBS/$1"
    chmod +x "$STUBS/$1"
}

# set_uid <n>: what `id -u` reports (root unless a test says otherwise).
set_uid() {
    printf '#!/bin/sh\necho %s\n' "$1" >"$STUBS/id"
    chmod +x "$STUBS/id"
}

@test "zz_install is on PATH and syntactically valid" {
    run sh -n "$(command -v zz_install)"
    [ "$status" -eq 0 ]
}

@test "zz_install with no argument prints usage and fails" {
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz_install uses the default package name with the first manager found" {
    stub apk
    stub dnf
    run_install jq
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "apk add --no-cache -q jq" ]
}

@test "zz_install applies the override for the selected manager" {
    stub dnf
    run_install git-flow apk=gitflow-avh dnf=gitflow
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "dnf install -y -q gitflow" ]
}

@test "zz_install ignores overrides for other managers" {
    stub apk
    run_install git-flow dnf=gitflow
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "apk add --no-cache -q git-flow" ]
}

@test "zz_install keys apt-get overrides as apt" {
    stub apt-get
    run_install git-flow apt=gitflow-x
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"apt-get install -y -qq gitflow-x" ]]
}

@test "zz_install goes through sudo when not root" {
    set_uid 1000
    stub apk
    stub sudo
    run_install jq
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "sudo apk add --no-cache -q jq" ]
}

@test "zz_install fails when not root and sudo is missing" {
    set_uid 1000
    stub apk
    run_install jq
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires root/sudo"* ]]
}

@test "zz_install fails when no package manager is found" {
    run_install jq
    [ "$status" -eq 1 ]
    [[ "$output" == *"No supported package manager"* ]]
}
