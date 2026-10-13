#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    # Local "remote": $WORK/remote/acme/tool.git
    mkdir -p "$WORK/src" "$WORK/remote/acme"
    git -C "$WORK/src" init -q -b main
    git -C "$WORK/src" config user.email t@t
    git -C "$WORK/src" config user.name t
    mkdir "$WORK/src/tool-setup"
    printf '#!/bin/sh\necho "ran:$*"\n' >"$WORK/src/tool-setup/run.sh"
    chmod +x "$WORK/src/tool-setup/run.sh"
    git -C "$WORK/src" add -A
    git -C "$WORK/src" commit -q -m init
    git clone -q --bare "$WORK/src" "$WORK/remote/acme/tool.git"
    export ZZ_RUN_URL_BASE="file://$WORK/remote" ZZ_RUN_DIR="$WORK/dir"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-run is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-run)"
    [ "$status" -eq 0 ]
}

@test "zz-run requires a repository argument" {
    run zz-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz-run rejects a malformed repository" {
    run zz-run notarepo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid repository"* ]]
}

@test "zz-run clones the repo and runs <repo>-setup/run.sh with the remaining args" {
    run zz-run acme/tool --flag x
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran:--flag x"* ]]
    [ -d "$WORK/dir/tool/.git" ]
}

@test "zz-run updates an existing checkout on a second run" {
    zz-run acme/tool
    printf '#!/bin/sh\necho "v2:$*"\n' >"$WORK/src/tool-setup/run.sh"
    git -C "$WORK/src" commit -q -am v2
    git -C "$WORK/src" push -q "$WORK/remote/acme/tool.git" main
    run zz-run acme/tool@main go
    [ "$status" -eq 0 ]
    [[ "$output" == *"v2:go"* ]]
}

@test "zz-run fails when the repo has no entrypoint" {
    git -C "$WORK/src" rm -q -r tool-setup
    git -C "$WORK/src" commit -q -m empty
    git -C "$WORK/src" push -q "$WORK/remote/acme/tool.git" main
    run zz-run acme/tool
    [ "$status" -eq 1 ]
    [[ "$output" == *"No entrypoint"* ]]
}
