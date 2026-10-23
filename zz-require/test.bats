#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-require is installed on PATH and syntactically valid" {
    command -v zz-require
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "zz-require errors for an unknown requirement" {
    run zz-require nonsense
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown requirement"* ]]
}

@test "zz-require root passes as root and names the step otherwise" {
    if [ "$(id -u)" -eq 0 ]; then
        run zz-require root
        [ "$status" -eq 0 ]
    fi
    stub_script id <<'STUB'
#!/bin/sh
echo 1000
STUB
    run zz-require -n my-step root
    [ "$status" -eq 1 ]
    [[ "$output" == *"my-step must run as root"* ]]
}

@test "zz-require os=<id> compares the /etc/os-release ID" {
    have=$(. /etc/os-release && printf '%s' "$ID")
    run zz-require "os=$have"
    [ "$status" -eq 0 ]
    run zz-require -n my-step os=notanos
    [ "$status" -eq 1 ]
    [[ "$output" == *"my-step targets notanos only"* ]]
}
