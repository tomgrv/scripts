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

# Workspace mode: root package.json with two "engines.zz-setup" workspaces; "b" depends
# on "a", "a" declares an input with a default.
make_workspace_remote() {
    rm -rf "$WORK/ws" "$WORK/remote/acme/ws.git"
    mkdir -p "$WORK/ws/a" "$WORK/ws/b" "$WORK/ws/lib"
    cd "$WORK/ws"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    echo '{"name":"ws","workspaces":["a","b","lib"]}' >package.json
    echo '{"name":"@x/a","bin":{"x":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":1,"default":false,"inputs":{"FOO":{"description":"foo","default":"bar"}}}}' >a/package.json
    echo '{"name":"@x/b","dependencies":{"@x/a":"*"},"bin":{"x":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":2,"default":false}}' >b/package.json
    echo '{"name":"@x/lib","engines":{"zz-setup":"*"}}' >lib/package.json
    mkdir -p str && echo '{"name":"@x/str","bin":{"x":"run.sh"},"engines":{"zz-setup":"*"}}' >str/package.json && printf '#!/bin/sh\necho str\n' >str/run.sh && chmod +x str/run.sh
    echo '{"name":"ws","workspaces":["a","b","lib","str"]}' >package.json
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
    run zz-setup acme/ws -o b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Also enabling"*"a"*"required by"* ]]
    [[ "$output" == *"a:up:bar"* ]]
    [[ "$output" == *"b:up"* ]]
    [[ "$output" != *"lib: up"* ]]
}

# "p" declares a conflict with "q"; "r" depends on "q" and so enables it.
make_conflict_remote() {
    rm -rf "$WORK/cf" "$WORK/remote/acme/cf.git"
    mkdir -p "$WORK/cf/p" "$WORK/cf/q" "$WORK/cf/r"
    cd "$WORK/cf"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    echo '{"name":"cf","workspaces":["p","q","r"]}' >package.json
    echo '{"name":"@x/p","bin":{"x":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":1,"conflicts":["@x/q"]}}' >p/package.json
    echo '{"name":"@x/q","bin":{"x":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":2}}' >q/package.json
    echo '{"name":"@x/r","dependencies":{"@x/q":"*"},"bin":{"x":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":3}}' >r/package.json
    for w in p q r; do printf '#!/bin/sh\necho "%s:$1"\n' "$w" >"$w/run.sh"; chmod +x "$w/run.sh"; done
    git add -A
    git commit -q -m init
    git clone -q --bare "$WORK/cf" "$WORK/remote/acme/cf.git"
    cd "$BATS_TEST_DIRNAME"
}

@test "zz-setup refuses conflicting workspaces before running anything, also through a dependency" {
    make_conflict_remote
    run zz-setup acme/cf -w p,q
    [ "$status" -eq 1 ]
    [[ "$output" == *"p"*"conflicts with"*"q"*"both are enabled"* ]]
    [[ "$output" != *"p:up"* ]]
    run zz-setup acme/cf -w p,r
    [ "$status" -eq 1 ]
    [[ "$output" == *"Also enabling"*"q"*"required by"* ]]
    [[ "$output" == *"p"*"conflicts with"*"q"*"both are enabled"* ]]
}

@test "zz-setup allows a conflicting pair when only one is up (the other skipped or coming down)" {
    make_conflict_remote
    run zz-setup acme/cf -o p
    [ "$status" -eq 0 ]
    [[ "$output" == *"p:up"* ]]
    run zz-setup acme/cf -w p -d q
    [ "$status" -eq 0 ]
    [[ "$output" == *"p:up"* ]]
    [[ "$output" == *"q:down"* ]]
}

@test "zz-setup honours inputs already set in the environment" {
    make_workspace_remote
    run env FOO=custom zz-setup acme/ws -w a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:custom"* ]]
}

@test "zz-setup runs a down step and refuses it while a dependent is up" {
    make_workspace_remote
    run zz-setup acme/ws -d a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:down"* ]]
    run zz-setup acme/ws -w b -d a
    [ "$status" -eq 1 ]
}

@test "zz-setup rejects an unknown workspace flag and does nothing when none is selected" {
    make_workspace_remote
    run zz-setup acme/ws -w nope
    [ "$status" -eq 1 ]
    run zz-setup acme/ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing selected"* ]]
}

@test "zz-setup -h lists only the runnable workspaces" {
    make_workspace_remote
    run zz-setup acme/ws -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"workspaces: a b str"* ]]
    [[ "$output" == *"-w <names>"* ]]
    [[ "$output" != *"lib"* ]]
}

@test "zz-setup takes comma/space separated workspace lists and rejects unknown arguments" {
    make_workspace_remote
    run zz-setup acme/ws -w a,b
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up"* && "$output" == *"b:up"* ]]
    run zz-setup acme/ws bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown argument:"*"bogus"* ]]
}

@test "zz-setup --status reports states and input status, and runs nothing" {
    make_workspace_remote
    run env FOO= zz-setup acme/ws -S -w b
    [ "$status" -eq 0 ]
    [[ "$output" == *"up"*"b"* ]]
    [[ "$output" == *"input FOO"*"[optional]"* ]]
    [[ "$output" != *"Running"* ]]
}

@test "zz-setup -d all brings every workspace down in reverse order" {
    make_workspace_remote
    run zz-setup acme/ws -D
    [ "$status" -eq 0 ]
    [[ "$output" == *"b:down"*"a:down"* ]]
}

@test "zz-setup keeps an input with an empty default and description in the right field" {
    make_workspace_remote
    jq '.config.inputs.BAR = {}' "$WORK/ws/a/package.json" >"$WORK/ws/a/p.json"
    mv "$WORK/ws/a/p.json" "$WORK/ws/a/package.json"
    git -C "$WORK/ws" commit -q -am bar
    git -C "$WORK/ws" push -q "$WORK/remote/acme/ws.git" main
    run zz-setup acme/ws -S
    [ "$status" -eq 0 ]
    [[ "$output" == *"input BAR"*" a"* ]]
}

@test "zz-setup persists caller-provided inputs via zz-persist (owner-only, quoted) and reuses them" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    run env FOO="it's a value" zz-setup acme/ws -w a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:it's a value"* ]]
    [ "$(stat -c %a "$WORK/run.env")" = 600 ]
    grep -qx "FOO=it's a value" "$WORK/run.env"
    run zz-setup acme/ws -w a
    [[ "$output" == *"a:up:it's a value"* ]]
}

@test "zz-setup lets the caller's environment win over the persisted env file" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    echo "FOO=old" >"$WORK/run.env"
    run env FOO=new zz-setup acme/ws -w a
    [[ "$output" == *"a:up:new"* ]]
    grep -qx "FOO=new" "$WORK/run.env"
}

@test "zz-setup reads the env file literally and never executes it" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/run.env"
    echo 'FOO=$(touch '"$WORK"'/pwned)' >"$WORK/run.env"
    run zz-setup acme/ws -w a
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/pwned" ]
    [[ "$output" == *'a:up:$(touch'* ]]
}

@test "zz-setup also exports persisted inputs from a profile.d snippet when ZZ_SETUP_PROFILE is set" {
    make_workspace_remote
    run env FOO="x y" ZZ_SETUP_PROFILE=zz-setup-test-$$ zz-setup acme/ws -w a
    [ "$status" -eq 0 ]
    # /etc/profile.d is not configurable and not writable without root (CI).
    if [ -f /etc/profile.d/zz-setup-test-$$.sh ]; then
        grep -qx "export FOO='x y'" /etc/profile.d/zz-setup-test-$$.sh
    fi
    rm -f /etc/profile.d/zz-setup-test-$$.sh
}

@test "zz-setup aborts before running anything when a required input is empty, and -s skips it" {
    make_workspace_remote
    jq '.config.inputs.NEEDED = {"required": true}' "$WORK/ws/a/package.json" >"$WORK/ws/a/p.json"
    mv "$WORK/ws/a/p.json" "$WORK/ws/a/package.json"
    git -C "$WORK/ws" commit -q -am needed
    git -C "$WORK/ws" push -q "$WORK/remote/acme/ws.git" main
    run zz-setup acme/ws -w a
    [ "$status" -eq 1 ]
    [[ "$output" == *"NEEDED is required by 'a'"* ]]
    [[ "$output" != *"a:up"* ]]
    run env NEEDED=x zz-setup acme/ws -w a
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up"* ]]
    run zz-setup acme/ws -w b -s a
    [ "$status" -eq 0 ]
}

@test "zz-setup runs a local checkout in place without cloning" {
    make_workspace_remote
    run zz-setup "$WORK/ws" -w a
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using the local checkout"* ]]
    [[ "$output" == *"a:up:bar"* ]]
    [ ! -d "$WORK/dir/ws" ]
}

@test "zz-setup remembers the state of each workspace it ran, down is stored as skip" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/state.env"
    run zz-setup acme/ws -o a
    [ "$status" -eq 0 ]
    grep -qx 'ZZ_STATE_a=up' "$ZZ_SETUP_ENV_FILE"
    ! grep -q 'ZZ_STATE_b' "$ZZ_SETUP_ENV_FILE"
    run zz-setup acme/ws -d a
    [ "$status" -eq 0 ]
    grep -qx 'ZZ_STATE_a=skip' "$ZZ_SETUP_ENV_FILE"
}

@test "zz-setup ignores remembered states without a menu" {
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/state.env"
    echo 'ZZ_STATE_a=up' >"$ZZ_SETUP_ENV_FILE"
    run zz-setup acme/ws </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing selected"* ]]
}

@test "zz-setup preselects the menu from the remembered states" {
    command -v script >/dev/null || skip "script(1) not available"
    make_workspace_remote
    export ZZ_SETUP_ENV_FILE="$WORK/state.env"
    echo 'ZZ_STATE_a=up' >"$ZZ_SETUP_ENV_FILE"
    run script -qec "zz-setup acme/ws" /dev/null < <(printf "\n\n")
    [ "$status" -eq 0 ]
    [[ "$output" == *"a:up:bar"* ]]
    [[ "$output" != *"b:up"* ]]
}

@test "zz-setup explains which ref variable applies when the fetch fails" {
    run zz-setup acme/tool@nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"ZZ_ORIGIN_REF"* ]]
}

@test "zz-setup shows a workspace's raw output as operation output when stdin is not a terminal" {
    make_workspace_remote
    run zz-setup acme/ws -o b </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"│ b:up"* ]]
}

@test "zz-setup hint lines sit one level under their error, behind a tree guide" {
    make_workspace_remote
    run zz-setup acme/ws -w nope </dev/null
    [ "$status" -ne 0 ]
    plain=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g')
    [[ "$plain" == *"|  Available: "* ]]
}
