#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "edit-script is installed on PATH and syntactically valid" {
    command -v edit-script
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "edit-script -h prints usage and exits non-zero" {
    run edit-script -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "edit-script errors without a script argument" {
    run edit-script
    [ "$status" -ne 0 ]
}

@test "edit-script fails when the script isn't installed in /usr/local/bin" {
    run edit-script definitely-not-installed-xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"not defined"* ]]
}

@test "edit-script copies an installed script locally, makes it executable, and opens it" {
    if [ ! -w /usr/local/bin ]; then
        skip "/usr/local/bin not writable in this environment"
    fi
    fake=/usr/local/bin/zz_test_edit_script_$$
    printf '#!/bin/sh\necho hi\n' >"$fake"
    chmod +x "$fake"

    # stub `code` (the editor invoked at the end of run.sh) so it's a no-op
    stub_dir=$(mktemp -d)
    printf '#!/bin/sh\nexit 0\n' >"$stub_dir/code"
    chmod +x "$stub_dir/code"

    name=$(basename "$fake")
    run env PATH="$stub_dir:$PATH" edit-script "$name"

    rm -f "$fake"
    rm -rf "$stub_dir"

    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/$name" ]
    [ -x "$WORK_DIR/$name" ]
}
