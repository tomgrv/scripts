#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_args emits eval-able var assignments" {
    run bash -c 'eval $(zz_args "t" "$0" -f value <<-help
f flag flag help text
help
); echo "$flag"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"value"* ]]
}
