#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz is installed on PATH and syntactically valid" {
    command -v zz
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "zz without arguments prints usage and fails" {
    run zz
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: zz <name>"* ]]
}

@test "zz -h prints usage" {
    run zz -h
    [[ "$output" == *"Usage: zz <name>"* ]]
}

@test "zz runs zz-<name> when it exists, forwarding arguments" {
    stub_script zz-hello <<'EOF'
#!/bin/sh
echo "hello:$*"
EOF
    run zz hello a "b c"
    [ "$status" -eq 0 ]
    [ "$output" = "hello:a b c" ]
}

@test "zz propagates the exit status of zz-<name>" {
    stub_script zz-fail <<'EOF'
#!/bin/sh
exit 7
EOF
    run zz fail
    [ "$status" -eq 7 ]
}

@test "zz prefers zz-<name> over installing <name>" {
    stub_script zz-hello <<'EOF'
#!/bin/sh
echo "dispatched"
EOF
    stub_script zz-use <<'EOF'
#!/bin/sh
echo "zz-use called: $*"
EOF
    run zz hello
    [ "$output" = "dispatched" ]
}

@test "zz falls back to zz-use -x <name> when zz-<name> does not exist" {
    stub_script zz-use <<'EOF'
#!/bin/sh
echo "zz-use called: $*"
EOF
    run zz nosuchthing one two
    [ "$status" -eq 0 ]
    [ "$output" = "zz-use called: -x nosuchthing one two" ]
}
