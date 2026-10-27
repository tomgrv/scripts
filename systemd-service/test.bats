#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    CALLS="$WORK/calls"
    : >"$CALLS"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

# stub_systemctl <is-active exit code>: record every call.
stub_systemctl() {
    printf '#!/bin/sh\necho "$*" >>"%s"\n[ "$1" = is-active ] && exit %s\nexit 0\n' "$CALLS" "$1" | stub_script systemctl
}

@test "systemd-service is installed on PATH and syntactically valid" {
    command -v systemd-service
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "systemd-service needs an action and a unit" {
    run systemd-service up
    [ "$status" -eq 1 ]
    run systemd-service sideways a
    [ "$status" -eq 1 ]
}

@test "up enables each unit and checks it is active" {
    stub_systemctl 0
    run systemd-service up a.service b.socket
    [ "$status" -eq 0 ]
    grep -q '^enable --now a.service$' "$CALLS"
    grep -q '^is-active --quiet b.socket$' "$CALLS"
    ! grep -q '^restart' "$CALLS"
}

@test "up -r restarts the units" {
    stub_systemctl 0
    run systemd-service -r up a.service
    [ "$status" -eq 0 ]
    grep -q '^restart a.service$' "$CALLS"
}

@test "up fails when a unit is not active" {
    stub_systemctl 3
    run systemd-service up a.service
    [ "$status" -eq 1 ]
    [[ "$output" == *"a.service is not active"* ]]
}

@test "down disables the units in one call and never fails" {
    printf '#!/bin/sh\necho "$*" >>"%s"\nexit 5\n' "$CALLS" | stub_script systemctl
    run systemd-service down a.service b.service
    [ "$status" -eq 0 ]
    grep -q '^disable --now a.service b.service$' "$CALLS"
}
