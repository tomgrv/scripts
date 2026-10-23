#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    # STUBS holds the fake package managers plus just the tools run.sh
    # needs: exposing /usr/bin would surface the host's real managers.
    STUBS=$(mktemp -d)
    for tool in sh cat tr sed awk grep dirname readlink basename cut expr; do
        ln -s "$(command -v $tool)" "$STUBS/$tool"
    done
    export CALLS="$STUBS/calls"
    set_uid 0
}

teardown() {
    rm -rf "$STUBS"
    teardown_scripts_path
}

# Run zz-install seeing only the stubs (bats itself keeps the full PATH).
run_install() {
    PATH="$TEST_BIN:$STUBS" run command zz-install "$@"
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

@test "zz-install is on PATH and syntactically valid" {
    run sh -n "$(command -v zz-install)"
    [ "$status" -eq 0 ]
}

@test "zz-install with no argument prints usage and fails" {
    run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz-install uses the default package name with the first manager found" {
    stub apk
    stub dnf
    run_install jq
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "apk add --no-cache -q jq" ]
}

@test "zz-install applies the override for the selected manager" {
    stub dnf
    run_install git-flow apk=gitflow-avh dnf=gitflow
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "dnf install -y -q gitflow" ]
}

@test "zz-install ignores overrides for other managers" {
    stub apk
    run_install git-flow dnf=gitflow
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "apk add --no-cache -q git-flow" ]
}

@test "zz-install -m skips recommended packages (apt, dnf)" {
    stub apt-get
    run_install -m jq
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"apt-get install -y -qq --no-install-recommends jq" ]]
}

@test "zz-install -r removes the package (apt purges, dnf removes)" {
    stub apt-get
    run_install -r jq
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"apt-get purge -y -qq jq" ]]
    rm -f "$STUBS/apt-get" "$CALLS"
    stub dnf
    run_install -r git-flow dnf=gitflow
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "dnf remove -y -q gitflow" ]
}

@test "zz-install installs several packages in one call, and removes them with -r" {
    stub apt-get
    run_install -m curl wget jq
    [ "$status" -eq 0 ]
    [ "$(grep -c 'apt-get install -y -qq --no-install-recommends' "$CALLS")" -eq 3 ]
    grep -q 'apt-get install -y -qq --no-install-recommends wget$' "$CALLS"
    : >"$CALLS"
    run_install -r curl wget
    [ "$(grep -c 'apt-get purge -y -qq' "$CALLS")" -eq 2 ]
}

@test "zz-install refuses overrides mixed with several packages" {
    stub apt-get
    run_install curl wget apt=wget2
    [ "$status" -ne 0 ]
}

@test "zz-install -u -x runs the downloaded script with the given shell, installing nothing" {
    payload=$(mktemp)
    printf 'echo ran-installer\n' >"$payload"
    bindir=$(mktemp -d)
    run env INSTALL_BIN_DIR="$bindir" zz-install -u "file://$payload" -x sh get-it
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-installer"* ]]
    [ -z "$(ls "$bindir")" ]
    run zz-install -x sh get-it
    [ "$status" -ne 0 ]
    rm -rf "$payload" "$bindir"
}

@test "zz-install keys apt-get overrides as apt" {
    stub apt-get
    run_install git-flow apt=gitflow-x
    [ "$status" -eq 0 ]
    [[ "$(cat "$CALLS")" == *"apt-get install -y -qq gitflow-x" ]]
}

@test "zz-install goes through sudo when not root" {
    set_uid 1000
    stub apk
    stub sudo
    run_install jq
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "sudo apk add --no-cache -q jq" ]
}

@test "zz-install installs through winget by exact name, without root" {
    set_uid 1000
    stub winget
    run_install jq winget=jqlang.jq
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "winget install -s winget -e --name jqlang.jq" ]
}

@test "zz-install fails when not root and sudo is missing" {
    set_uid 1000
    stub apk
    run_install jq
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires root/sudo"* ]]
}

@test "zz-install fails when no package manager is found" {
    run_install jq
    [ "$status" -eq 1 ]
    [[ "$output" == *"No supported package manager"* ]]
}

@test "zz-install -u downloads a raw binary into the bin dir and checks its sha256" {
    payload=$(mktemp)
    printf '#!/bin/sh\necho downloaded\n' >"$payload"
    bindir=$(mktemp -d)
    sum=$(sha256sum "$payload" | cut -d' ' -f1)
    run env INSTALL_BIN_DIR="$bindir" zz-install -u "file://$payload" -s "$sum" fake-tool
    [ "$status" -eq 0 ]
    [ "$("$bindir/fake-tool")" = downloaded ]
    rm -f "$bindir/fake-tool"
    run env INSTALL_BIN_DIR="$bindir" zz-install -u "file://$payload" -s 0000 fake-tool
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum mismatch"* ]]
    rm -rf "$payload" "$bindir"
}
