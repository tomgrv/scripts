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
    export ZZ_SETUP_URL_BASE="file://$WORK/remote" ZZ_SETUP_DIR="$WORK/dir" ZZ_SETUP_ENV_FILE="$WORK/default.env"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-setup is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-setup)"
    [ "$status" -eq 0 ]
}

@test "zz-setup requires a repository argument" {
    run zz-setup
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz-setup rejects a malformed repository" {
    run zz-setup notarepo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid repository"* ]]
}

@test "zz-setup clones the repo and runs <repo>-setup/run.sh with the remaining args" {
    run zz-setup acme/tool --flag x
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran:--flag x"* ]]
    [ -d "$WORK/dir/tool/.git" ]
}

@test "zz-setup updates an existing checkout on a second run" {
    zz-setup acme/tool
    printf '#!/bin/sh\necho "v2:$*"\n' >"$WORK/src/tool-setup/run.sh"
    git -C "$WORK/src" commit -q -am v2
    git -C "$WORK/src" push -q "$WORK/remote/acme/tool.git" main
    run zz-setup acme/tool@main go
    [ "$status" -eq 0 ]
    [[ "$output" == *"v2:go"* ]]
}

@test "zz-setup fails when the repo has no entrypoint" {
    git -C "$WORK/src" rm -q -r tool-setup
    git -C "$WORK/src" commit -q -m empty
    git -C "$WORK/src" push -q "$WORK/remote/acme/tool.git" main
    run zz-setup acme/tool
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

@test "zz-setup runs the selected workspace, enabling its dependency first, with input defaults" {
    make_workspace_remote
    run zz-setup acme/ws --only-b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Also enabling 'a'"* ]]
    [[ "$output" == *"a:up:bar"* ]]
    [[ "$output" == *"b:up"* ]]
    [[ "$output" != *"lib"*"Running"* ]]
}

@test "zz-setup honours inputs already set in the environment" {
    make_workspace_remote
    run env FOO=custom zz-setup acme/ws --with-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:custom"* ]]
}

@test "zz-setup runs a down step and refuses it while a dependent is up" {
    make_workspace_remote
    run zz-setup acme/ws --down-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:down"* ]]
    run zz-setup acme/ws --with-b --down-a
    [ "$status" -eq 1 ]
}

@test "zz-setup rejects an unknown workspace flag and does nothing when none is selected" {
    make_workspace_remote
    run zz-setup acme/ws --with-nope
    [ "$status" -eq 1 ]
    run zz-setup acme/ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing selected"* ]]
}

@test "zz-setup -h lists only the runnable vps workspaces" {
    make_workspace_remote
    run zz-setup acme/ws -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"--with-a"* ]]
    [[ "$output" != *"--with-lib"* ]]
}

@test "zz-setup --status reports states and input status, and runs nothing" {
    make_workspace_remote
    run env FOO= zz-setup acme/ws --status --with-b
    [ "$status" -eq 0 ]
    [[ "$output" == *"up"*"b"* ]]
    [[ "$output" == *"input FOO"*"[optional]"* ]]
    [[ "$output" != *"Running"* ]]
}

@test "zz-setup --down-all brings every workspace down in reverse order" {
    make_workspace_remote
    run zz-setup acme/ws --down-all
    [ "$status" -eq 0 ]
    [[ "$output" == *"b:down"*"a:down"* ]]
}

@test "zz-setup keeps an input with an empty default and description in the right field" {
    make_workspace_remote
    jq '.vps.inputs.BAR = {}' "$WORK/ws/a/package.json" >"$WORK/ws/a/p.json"
    mv "$WORK/ws/a/p.json" "$WORK/ws/a/package.json"
    git -C "$WORK/ws" commit -q -am bar
    git -C "$WORK/ws" push -q "$WORK/remote/acme/ws.git" main
    run zz-setup acme/ws --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"input BAR"*" a"* ]]
}

@test "zz-setup persists caller-provided inputs via zz-persist (owner-only, quoted) and reuses them" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    run env FOO="it's a value" zz-setup acme/ws --with-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:it's a value"* ]]
    [ "$(stat -c %a "$WORK/run.env")" = 600 ]
    grep -qx "FOO=it's a value" "$WORK/run.env"
    run zz-setup acme/ws --with-a
    [[ "$output" == *"a:up:it's a value"* ]]
}

@test "zz-setup lets the caller's environment win over the persisted env file" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    echo "FOO=old" >"$WORK/run.env"
    run env FOO=new zz-setup acme/ws --with-a
    [[ "$output" == *"a:up:new"* ]]
    grep -qx "FOO=new" "$WORK/run.env"
}

@test "zz-setup reads the env file literally and never executes it" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    echo 'FOO=$(touch '"$WORK"'/pwned)' >"$WORK/run.env"
    run zz-setup acme/ws --with-a
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/pwned" ]
    [[ "$output" == *'a:up:$(touch'* ]]
}

@test "zz-setup also exports persisted inputs from a profile.d snippet when ZZ_SETUP_PROFILE is set" {
    make_workspace_remote
    run env FOO="x y" ZZ_SETUP_PROFILE=zz-setup-test-$$ zz-setup acme/ws --with-a
    [ "$status" -eq 0 ]
    grep -qx "export FOO='x y'" /etc/profile.d/zz-setup-test-$$.sh
    rm -f /etc/profile.d/zz-setup-test-$$.sh
}
