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

@test "distribute-utils is installed on PATH and syntactically valid" {
    command -v distribute-utils
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "distribute-utils -h prints usage and exits non-zero" {
    run distribute-utils -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "distribute-utils errors without a target directory" {
    run distribute-utils
    [ "$status" -ne 0 ]
    [[ "$output" == *"No target directory"* ]]
}

@test "distribute-utils exits quietly with -q and no target" {
    run distribute-utils -q
    [ "$status" -eq 0 ]
}

@test "distribute-utils errors when the resolved target directory doesn't exist" {
    run distribute-utils -t "$WORK_DIR/does-not-exist"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "distribute-utils reads target from .zz_dist when -t is not given" {
    mkdir -p target src
    echo "$WORK_DIR/target" >.zz_dist
    touch src/zz_foo.sh && chmod +x src/zz_foo.sh
    run distribute-utils -s "$WORK_DIR/src"
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/zz_foo.sh" ]
}

@test "distribute-utils reads target from package.json config.zz_dist" {
    mkdir -p target src
    cat >package.json <<EOF
{"config": {"zz_dist": "$WORK_DIR/target"}}
EOF
    touch src/zz_foo.sh && chmod +x src/zz_foo.sh
    run distribute-utils -s "$WORK_DIR/src"
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/zz_foo.sh" ]
}

@test "distribute-utils succeeds as a no-op when the given source directory does not exist" {
    mkdir -p target
    run distribute-utils -t "$WORK_DIR/target" -s "$WORK_DIR/nonexistent-source"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$WORK_DIR/target")" ]
}

@test "distribute-utils copies executable zz_* files, stripping the leading underscore and .sh suffix from _zz_*.sh files" {
    mkdir -p target src
    echo '#!/bin/sh' >src/zz_plain.sh
    chmod +x src/zz_plain.sh
    echo '#!/bin/sh' >src/_zz_hidden.sh
    chmod +x src/_zz_hidden.sh
    run distribute-utils -t "$WORK_DIR/target" -s "$WORK_DIR/src"
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/zz_plain.sh" ]
    [ -f "$WORK_DIR/target/zz_hidden" ]
    [ ! -f "$WORK_DIR/target/_zz_hidden.sh" ]
}

@test "distribute-utils skips non-executable zz_* files" {
    mkdir -p target src
    echo '#!/bin/sh' >src/zz_noexec.sh
    chmod -x src/zz_noexec.sh
    run distribute-utils -t "$WORK_DIR/target" -s "$WORK_DIR/src"
    [ "$status" -eq 0 ]
    [ ! -f "$WORK_DIR/target/zz_noexec.sh" ]
}

@test "distribute-utils makes copied files executable in the target" {
    mkdir -p target src
    echo '#!/bin/sh' >src/zz_exec.sh
    chmod +x src/zz_exec.sh
    run distribute-utils -t "$WORK_DIR/target" -s "$WORK_DIR/src"
    [ "$status" -eq 0 ]
    [ -x "$WORK_DIR/target/zz_exec.sh" ]
}
