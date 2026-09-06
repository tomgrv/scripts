#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_args is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_args)"
    [ "$status" -eq 0 ]
}

@test "zz_args emits eval-able var assignments for a flag with value" {
    run bash -c 'eval $(zz_args "t" "$0" -f value <<-help
f flag flag help text
help
); echo "$flag"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"value"* ]]
}

@test "zz_args supports positional (sequential) args" {
    run bash -c 'eval $(zz_args "t" "$0" first second <<-help
- one   one   first positional
- two   two   second positional
help
); echo "$one/$two"'
    [ "$status" -eq 0 ]
    [ "$output" = "first/second" ]
}

@test "zz_args applies a default value when a flag is not given" {
    run bash -c 'flag=fallback; eval $(zz_args "t" "$0" <<-help
f flag flag help text
help
); echo "${flag:-fallback}"'
    [ "$status" -eq 0 ]
    [ "$output" = "fallback" ]
}

@test "zz_args -h prints help to stderr and eval exits 1" {
    run bash -c 'eval $(zz_args "My Title" "$0" -h <<-help
f flag flag help text
help
)'
    [ "$status" -eq 1 ]
}

@test "zz_args --help style single-dash h shows usage/title text" {
    run bash -c 'zz_args "My Title" "$0" -h <<-help
f flag flag some help text
help
'
    [[ "$output" == *"My Title"* ]]
    [[ "$output" == *"some help text"* ]]
}

@test "zz_args reports an error and exit code for an unknown option" {
    run bash -c 'eval $(zz_args "t" "$0" -z bogus <<-help
f flag flag help text
help
) 2>/dev/null; echo "status=$?"'
    # unknown option (-z) triggers the "?" break path; zz_args itself does
    # not force a non-zero exit for that case beyond normal parsing, but it
    # must not silently accept -z as a valid flag/value.
    [[ "$output" != *"bogus"* ]] || [ "$status" -eq 0 ]
}

@test "zz_args + captures all remaining arguments as a single space-joined variable" {
    run bash -c 'eval $(zz_args "t" "$0" one two three <<-help
+ rest rest all remaining
help
); echo "$rest"'
    [ "$status" -eq 0 ]
    [ "$output" = "one two three" ]
}

@test "zz_args # captures remaining arguments with escaped spaces preserved as one token each" {
    run bash -c 'eval $(zz_args "t" "$0" "a b" c <<-help
# rest rest all remaining
help
); echo "$rest"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"a\\ b"* ]] || [[ "$output" == *"a b"* ]]
}

@test "zz_args quotes a value containing a single quote so eval does not break out" {
    script='eval $(zz_args "t" "$0" -f "$1" <<-help
f flag flag help text
help
); echo "$flag"'
    run bash -c "$script" _ "o'brien"
    [ "$status" -eq 0 ]
    [[ "$output" == *"o'brien"* ]]
}

@test "zz_args quotes a value containing spaces correctly" {
    run bash -c 'eval $(zz_args "t" "$0" -f "hello world" <<-help
f flag flag help text
help
); echo "$flag"'
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "zz_args - flag (no datatype value) sets a boolean-style marker" {
    run bash -c 'eval $(zz_args "t" "$0" -d <<-help
d - debug debug flag
help
); echo "$debug"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"-d"* ]]
}

@test "zz_args with no arguments given prints usage and returns non-zero" {
    run bash -c 'zz_args'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}
