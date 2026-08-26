#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "dispatch-script requires a subcommand" {
    run dispatch-script "_foo.sh"
    [ "$status" -ne 0 ]
}

@test "dispatch-script executes the matching sibling script" {
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho ran-ok\n' >"$dir/foo-bar.sh"
    chmod +x "$dir/foo-bar.sh"
    run dispatch-script "$dir/_foo.sh" bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-ok"* ]]
    rm -rf "$dir"
}
