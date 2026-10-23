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
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "ws-list is installed on PATH and syntactically valid" {
    command -v ws-list
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "ws-list -h prints usage and exits non-zero" {
    run ws-list -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ws-list falls back to listing all top-level directories with no package.json" {
    mkdir -p dir1 dir2
    touch file.txt
    run ws-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"./dir1"* ]]
    [[ "$output" == *"./dir2"* ]]
}

@test "ws-list lists directories matching package.json workspaces globs" {
    mkdir -p packages/a packages/b other
    touch packages/a/f packages/b/f other/f
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    run ws-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"packages/a"* ]]
    [[ "$output" == *"packages/b"* ]]
    [[ "$output" != *"./other"* ]]
}

@test "ws-list lists a literal (non-glob) workspace entry" {
    mkdir -p libs/core
    cat >package.json <<'EOF'
{"workspaces": ["libs/core"]}
EOF
    run ws-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"libs/core"* ]]
}

@test "ws-list -r reports only workspaces touched within a commit range" {
    mkdir -p packages/a packages/b
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    touch packages/a/f packages/b/f
    git add -A
    git commit -q -m "initial"

    echo changed >packages/a/f
    git add -A
    git commit -q -m "touch a"

    run ws-list -r HEAD~1..HEAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"packages/a"* ]]
    [[ "$output" != *"packages/b"* ]]
}

@test "ws-list -r prints nothing when the range touches no workspace" {
    mkdir -p packages/a
    cat >package.json <<'EOF'
{"workspaces": ["packages/*"]}
EOF
    touch packages/a/f
    git add -A
    git commit -q -m "initial"
    git commit -q --allow-empty -m "empty change"

    run ws-list -r HEAD~1..HEAD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# -b / -e / -o: filter by bin / engines.<name>, order by config.order
make_modules() {
    mkdir -p a b c
    echo '{"workspaces":["a","b","c"]}' >package.json
    echo '{"name":"a","bin":{"a":"run.sh"},"engines":{"zz-setup":"*"},"config":{"order":20}}' >a/package.json
    echo '{"name":"b","bin":"run.sh","engines":{"zz-setup":"*"},"config":{"order":10}}' >b/package.json
    echo '{"name":"c","bin":"run.sh"}' >c/package.json
    touch a/run.sh b/run.sh c/run.sh
}

@test "ws-list -b -e zz-setup keeps the runnable workspaces" {
    make_modules
    run ws-list -b -e zz-setup
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "./a ./b " ]
}

@test "ws-list -b skips a workspace whose bin file is missing" {
    make_modules
    rm b/run.sh
    run ws-list -b
    [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "./a ./c " ]
}

@test "ws-list -o sorts by config.order" {
    make_modules
    run ws-list -b -e zz-setup -o
    [ "$output" = "$(printf './b\n./a')" ]
}

@test "ws-list accepts a directory and the workspaces.packages form" {
    make_modules
    echo '{"workspaces":{"packages":["a"]}}' >package.json
    cd /
    run ws-list "$WORK_DIR"
    [ "$output" = "./a" ]
}
