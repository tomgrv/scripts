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

@test "resolve-context is installed on PATH and syntactically valid" {
    command -v resolve-context
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "resolve-context -h prints usage and exits non-zero" {
    run resolve-context -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "resolve-context resolves source/feature/target from an explicit caller" {
    mkdir -p feature_dir
    touch feature_dir/install.sh
    run resolve-context -t "$WORK_DIR/target" -- "$WORK_DIR/feature_dir/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"feature="* ]]
    [[ "$output" == *"target="* ]]
    [[ "$output" == *"feature=feature_dir"* ]]
    [ -d "$WORK_DIR/target" ]
}

@test "resolve-context strips a trailing _NNN suffix from the feature name" {
    mkdir -p "myfeature_42"
    touch "myfeature_42/install.sh"
    run resolve-context -t "$WORK_DIR/target" -- "$WORK_DIR/myfeature_42/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"feature=myfeature"* ]]
}

@test "resolve-context honors an explicit -s source over the caller path" {
    mkdir -p forced_source
    mkdir -p feature_dir
    touch feature_dir/install.sh
    run resolve-context -s "$WORK_DIR/forced_source" -t "$WORK_DIR/target" -- "$WORK_DIR/feature_dir/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source=$WORK_DIR/forced_source"* ]]
    [[ "$output" == *"feature=forced_source"* ]]
}

@test "resolve-context creates the target directory when it doesn't exist" {
    mkdir -p feature_dir
    touch feature_dir/install.sh
    [ ! -d "$WORK_DIR/newtarget" ]
    run resolve-context -t "$WORK_DIR/newtarget" -- "$WORK_DIR/feature_dir/install.sh"
    [ "$status" -eq 0 ]
    [ -d "$WORK_DIR/newtarget" ]
}

@test "resolve-context defaults target under /usr/local/share when writable" {
    if [ ! -w /usr/local/share ]; then
        skip "/usr/local/share not writable in this environment"
    fi
    mkdir -p feature_dir
    touch feature_dir/install.sh
    run resolve-context -- "$WORK_DIR/feature_dir/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target=/usr/local/share/feature_dir"* ]]
    rm -rf /usr/local/share/feature_dir
}
