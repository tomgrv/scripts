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

@test "feature-install is installed on PATH and syntactically valid" {
    command -v feature-install
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "feature-install -h prints usage and exits non-zero" {
    run feature-install -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "feature-install errors without a caller argument" {
    run feature-install
    [ "$status" -ne 0 ]
}

@test "feature-install copies stubs/config/bin from source to target" {
    mkdir -p src/stubs/sub src/config src/bin
    echo hello >src/stubs/sub/file.txt
    echo '{}' >src/config/settings.json
    printf '#!/bin/sh\necho hi\n' >src/bin/tool.sh

    run feature-install -s "$WORK_DIR/src" -t "$WORK_DIR/target" caller
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/stubs/sub/file.txt" ]
    [ -f "$WORK_DIR/target/config/settings.json" ]
    [ -f "$WORK_DIR/target/bin/tool.sh" ]
}

@test "feature-install copies configure-*.sh lifecycle scripts into the target" {
    mkdir -p src
    echo '#!/bin/sh' >src/configure-thing.sh

    run feature-install -s "$WORK_DIR/src" -t "$WORK_DIR/target" caller
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/configure-thing.sh" ]
    [ -x "$WORK_DIR/target/configure-thing.sh" ]
}

@test "feature-install runs install-*.sh lifecycle scripts from the source" {
    mkdir -p src
    cat >src/install-thing.sh <<EOF
#!/bin/sh
touch "$WORK_DIR/install-ran.txt"
EOF
    chmod +x src/install-thing.sh

    run feature-install -s "$WORK_DIR/src" -t "$WORK_DIR/target" caller
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/install-ran.txt" ]
}

@test "feature-install symlinks bin/*.sh scripts (stripping .sh) onto a writable bin dir" {
    mkdir -p src/bin
    printf '#!/bin/sh\necho hi\n' >src/bin/mytool.sh
    chmod +x src/bin/mytool.sh

    run feature-install -s "$WORK_DIR/src" -t "$WORK_DIR/target" caller
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/target/bin/mytool.sh" ]
    # a symlink named "mytool" (no .sh) exists somewhere on the writable PATH
    found=0
    old_ifs=$IFS
    IFS=':'
    for dir in $PATH; do
        [ -L "$dir/mytool" ] && found=1
    done
    IFS=$old_ifs
    [ "$found" -eq 1 ]
}

@test "feature-install warns but succeeds when source has no stubs/config" {
    mkdir -p src
    touch src/somefile

    run feature-install -s "$WORK_DIR/src" -t "$WORK_DIR/target" caller
    [ "$status" -eq 0 ]
    [[ "$output" == *"No stubs found"* ]]
}
