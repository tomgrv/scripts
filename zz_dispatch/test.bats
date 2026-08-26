#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_dispatch requires a subcommand" {
    run zz_dispatch "_foo.sh"
    [ "$status" -ne 0 ]
}

@test "zz_dispatch executes the matching sibling script" {
    # The dispatch target is looked up without a .sh extension (it's meant
    # to find an installed, extension-stripped sibling, e.g. one linked by
    # zz_bindir) — so the fixture here has none either.
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho ran-ok\n' >"$dir/foo-bar"
    chmod +x "$dir/foo-bar"
    run zz_dispatch "$dir/_foo.sh" bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-ok"* ]]
    rm -rf "$dir"
}
