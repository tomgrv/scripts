#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_use skips a tool already on PATH" {
    run zz_use sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"already available"* ]]
}

@test "zz_use requires at least one tool argument" {
    run zz_use
    [ "$status" -ne 0 ]
}

@test "zz_use installs a functional script individually, not the whole bundle" {
    bindir=$(mktemp -d)
    # PATH is restricted to hide load-json/validate-json (already linked
    # onto TEST_BIN by setup_scripts_path, which would make load-json
    # trivially "already available" instead of exercising real install
    # logic) — but zz_use itself is resolved to an absolute path first, so
    # restricting PATH for the child doesn't also hide zz_use.
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" load-json
    [ "$status" -eq 0 ]
    [ -x "$bindir/load-json" ]
    [ ! -e "$bindir/validate-json" ]
    rm -rf "$bindir"
}
