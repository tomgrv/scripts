#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    git -C "$WORK" init -q -b main src
    git -C "$WORK/src" config user.email t@t
    git -C "$WORK/src" config user.name t
    echo one >"$WORK/src/f"
    git -C "$WORK/src" add -A
    git -C "$WORK/src" commit -q -m one
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-fetch without url or dir prints usage and fails" {
    run zz-fetch
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz-fetch clones into a new directory" {
    run zz-fetch -d "$WORK/out/co" "file://$WORK/src"
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/out/co/f")" = one ]
}

@test "zz-fetch fast-forwards an existing checkout and drops local changes" {
    zz-fetch -d "$WORK/co" "file://$WORK/src" 2>/dev/null
    echo two >"$WORK/src/f"
    git -C "$WORK/src" commit -q -am two
    echo dirty >"$WORK/co/f"
    run zz-fetch -d "$WORK/co" "file://$WORK/src"
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/co/f")" = two ]
}

@test "zz-fetch uses an existing non-git directory in place" {
    mkdir "$WORK/plain"
    run zz-fetch -d "$WORK/plain" "file://$WORK/src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a git checkout"* ]]
}

@test "zz-fetch forwards git failures as operation output and fails" {
    run zz-fetch -d "$WORK/co" "file://$WORK/nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"│"* ]]
}
