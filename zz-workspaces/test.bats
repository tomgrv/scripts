#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    mkdir -p "$WORK/a" "$WORK/b" "$WORK/c"
    echo '{"workspaces":["a","b","c"]}' >"$WORK/package.json"
    echo '{"name":"@x/a","description":"Alpha","bin":{"a":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":20,"default":true,"conflicts":["@x/b"]},"peerDependencies":{"@x/b":"*"}}' >"$WORK/a/package.json"
    echo '{"name":"@x/b","bin":"run.sh","engines":{"zz-setup":"*"},"config":{"order":10}}' >"$WORK/b/package.json"
    echo '{"name":"@x/c","bin":"run.sh"}' >"$WORK/c/package.json"
    touch "$WORK/a/run.sh" "$WORK/b/run.sh" "$WORK/c/run.sh"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-workspaces lists runnable workspaces sorted by order, one row each" {
    run zz-workspaces "$WORK"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
    us=$(printf '\037')
    [ "$(printf '%s\n' "$output" | sed -n 1p)" = "10${us}b${us}b${us}${us}false${us}${us}${us}run.sh${us}false${us}${us}false" ]
    [ "$(printf '%s\n' "$output" | sed -n 2p)" = "20${us}a${us}a${us}Alpha${us}true${us}b${us}b${us}run.sh${us}false${us}${us}false" ]
}

@test "zz-workspaces skips a workspace whose bin file is missing" {
    rm "$WORK/b/run.sh"
    run zz-workspaces "$WORK"
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
    [ "$(printf '%s\n' "$output" | cut -d"$(printf '\037')" -f2)" = a ]
}

@test "zz-workspaces prints nothing without a package.json" {
    rm "$WORK/package.json"
    run zz-workspaces "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
