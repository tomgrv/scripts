#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    git commit -q --allow-empty -m "init"
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "configure-feature is installed on PATH and syntactically valid" {
    command -v configure-feature
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "configure-feature -h prints usage and exits non-zero" {
    run configure-feature -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "configure-feature errors without a feature argument" {
    run configure-feature
    [ "$status" -ne 0 ]
}

@test "configure-feature errors when the source directory does not exist" {
    run configure-feature -s "$WORK_DIR/nonexistent" myfeature
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "configure-feature copies a new plain-text stub file into the cwd" {
    mkdir -p src/stubs
    echo "line1" >src/stubs/plain.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/plain.txt" ]
    grep -q line1 "$WORK_DIR/plain.txt"
}

@test "configure-feature merges a json stub into an existing json file" {
    mkdir -p src/stubs
    echo '{"b":2}' >src/stubs/config.json
    echo '{"a":1}' >config.json
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    result=$(cat config.json)
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
}

@test "configure-feature copies a json stub as-is when destination doesn't exist" {
    mkdir -p src/stubs
    echo '{"a":1}' >src/stubs/newfile.json
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f newfile.json ]
    grep -q '"a"' newfile.json
}

@test "configure-feature reconciles a fragment additively into an existing plain-text file" {
    mkdir -p src/stubs
    printf 'line1\nline2\n' >src/stubs/frag.txt
    printf 'existing1\n' >frag.txt

    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    grep -q existing1 frag.txt
    grep -q line1 frag.txt
    grep -q line2 frag.txt
}

@test "configure-feature strips a leading underscore prefix from stub filenames" {
    mkdir -p src/stubs
    echo "content" >src/stubs/_prefix.actual.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f actual.txt ]
    [ ! -f _prefix.actual.txt ]
}

@test "configure-feature adds hash-prefixed stub destinations to .gitignore" {
    mkdir -p src/stubs
    echo "secretcontent" >'src/stubs/#ignored.txt'
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f ignored.txt ]
    grep -qxF "./ignored.txt" .gitignore
}

@test "configure-feature preserves executable permission bits from stub source" {
    mkdir -p src/stubs
    printf '#!/bin/sh\necho hi\n' >src/stubs/exec.sh
    chmod 755 src/stubs/exec.sh
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -x exec.sh ]
}

@test "configure-feature deploys stub symlinks when the destination doesn't already exist" {
    mkdir -p src/stubs
    echo "target-content" >src/stubs/real.txt
    ln -s real.txt src/stubs/linked.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -L linked.txt ]
}

@test "configure-feature runs configure-*.sh scripts from source when at repo top level" {
    cat >src-configure.sh <<'EOF'
EOF
    mkdir -p src
    cat >"src/configure-thing.sh" <<EOF
#!/bin/sh
touch "$WORK_DIR/configure-ran.txt"
EOF
    chmod +x src/configure-thing.sh
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/configure-ran.txt" ]
}

@test "configure-feature skips configure-*.sh scripts when not at repo top level" {
    mkdir -p src sub
    cat >"src/configure-thing.sh" <<EOF
#!/bin/sh
touch "$WORK_DIR/configure-ran-sub.txt"
EOF
    chmod +x src/configure-thing.sh
    cd sub
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ ! -f "$WORK_DIR/configure-ran-sub.txt" ]
    [[ "$output" == *"Not in top level directory"* ]]
}
