#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_use is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_use)"
    [ "$status" -eq 0 ]
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

@test "zz_use installs the full zz_* bundle at once when any one zz_* tool is missing" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz_log
    [ "$status" -eq 0 ]
    for tool in zz_use zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist zz_call zz_update; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

@test "zz_use errors out for a tool that cannot be resolved by any install path" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" totally-bogus-tool-xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unable to provide required dependency"* ]]
    rm -rf "$bindir"
}

@test "zz_use --force re-installs the zz_* bundle even when already on PATH" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    # First install normally so files exist with an old mtime, then force
    # a re-install and check it does not merely say "already available".
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz_log
    [ "$status" -eq 0 ]
    run env INSTALL_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" "$zz_use_bin" --force zz_log
    [ "$status" -eq 0 ]
    [[ "$output" != *"already available"* ]]
    rm -rf "$bindir"
}

@test "zz_use resolves a functional script's config/ folder alongside it" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" validate-json
    [ "$status" -eq 0 ]
    [ -x "$bindir/validate-json" ]
    rm -rf "$bindir"
}
