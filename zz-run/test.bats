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
    [[ "$output" == *"No workspace or entrypoint"* ]]
}

# Workspace mode: root package.json with two "vps" workspaces; "b" depends
# on "a", "a" declares an input with a default.
make_workspace_remote() {
    rm -rf "$WORK/ws" "$WORK/remote/acme/ws.git"
    mkdir -p "$WORK/ws/a" "$WORK/ws/b" "$WORK/ws/lib"
    cd "$WORK/ws"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    echo '{"name":"ws","workspaces":["a","b","lib"]}' >package.json
    echo '{"name":"@x/a","vps":{"order":1,"default":false,"inputs":{"FOO":{"description":"foo","default":"bar"}}}}' >a/package.json
    echo '{"name":"@x/b","dependencies":{"@x/a":"*"},"vps":{"order":2,"default":false}}' >b/package.json
    echo '{"name":"@x/lib"}' >lib/package.json
    printf '#!/bin/sh\necho "a:$1:$FOO"\n' >a/run.sh
    printf '#!/bin/sh\necho "b:$1"\n' >b/run.sh
    printf '#!/bin/sh\necho "lib"\n' >lib/run.sh
    chmod +x a/run.sh b/run.sh lib/run.sh
    git add -A
    git commit -q -m init
    git clone -q --bare "$WORK/ws" "$WORK/remote/acme/ws.git"
    cd "$BATS_TEST_DIRNAME"
}

@test "zz-run runs the selected workspace, enabling its dependency first, with input defaults" {
    make_workspace_remote
    run zz-run acme/ws --only-b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Also enabling 'a'"* ]]
    [[ "$output" == *"a:up:bar"* ]]
    [[ "$output" == *"b:up"* ]]
    [[ "$output" != *"lib"*"Running"* ]]
}

@test "zz-run honours inputs already set in the environment" {
    make_workspace_remote
    run env FOO=custom zz-run acme/ws --with-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:custom"* ]]
}

@test "zz-run runs a down step and refuses it while a dependent is up" {
    make_workspace_remote
    run zz-run acme/ws --down-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:down"* ]]
    run zz-run acme/ws --with-b --down-a
    [ "$status" -eq 1 ]
}

@test "zz-run rejects an unknown workspace flag and does nothing when none is selected" {
    make_workspace_remote
    run zz-run acme/ws --with-nope
    [ "$status" -eq 1 ]
    run zz-run acme/ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing selected"* ]]
}

@test "zz-run -h lists only the runnable vps workspaces" {
    make_workspace_remote
    run zz-run acme/ws -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"--with-a"* ]]
    [[ "$output" != *"--with-lib"* ]]
}
