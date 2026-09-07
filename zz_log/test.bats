#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_log is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_log)"
    [ "$status" -eq 0 ]
}

@test "zz_log prints a leveled message to stderr" {
    run zz_log i "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "zz_log supports i/n/w/e/s/- levels without erroring" {
    for lvl in i n w e s -; do
        run zz_log "$lvl" "msg"
        [ "$status" -eq 0 ]
    done
}

@test "zz_log writes to stderr, not stdout" {
    run bash -c 'zz_log i "onstderr" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c 'zz_log i "onstderr" 1>/dev/null'
    [[ "$output" == *"onstderr"* ]]
}

@test "zz_log info level uses the info pictogram/arrow" {
    run bash -c 'zz_log i "hi" 2>&1'
    [[ "$output" == *"→"* ]]
}

@test "zz_log notice level uses the notice (cyan) pictogram" {
    run bash -c 'zz_log n "heads up" 2>&1'
    [[ "$output" == *$'\033[1;36m'* ]]
    [[ "$output" == *"heads up"* ]]
    [[ "$output" != *"✕"* ]]
    [[ "$output" != *"✔"* ]]
}

@test "zz_log warning level uses the warning pictogram" {
    run bash -c 'zz_log w "careful" 2>&1'
    [[ "$output" == *"!"* ]]
    [[ "$output" == *"careful"* ]]
}

@test "zz_log error level uses the error pictogram" {
    run bash -c 'zz_log e "boom" 2>&1'
    [[ "$output" == *"✕"* ]]
    [[ "$output" == *"boom"* ]]
}

@test "zz_log success level uses the success pictogram" {
    run bash -c 'zz_log s "done" 2>&1'
    [[ "$output" == *"✔"* ]]
    [[ "$output" == *"done"* ]]
}

@test "zz_log plain (-) level has no pictogram, just indentation" {
    run bash -c 'zz_log - "plainmsg" 2>&1'
    [[ "$output" == *"plainmsg"* ]]
    [[ "$output" != *"✕"* ]]
    [[ "$output" != *"✔"* ]]
}

@test "zz_log joins multiple message words with spaces" {
    run bash -c 'zz_log i one two three 2>&1'
    [[ "$output" == *"one two three"* ]]
}

@test "zz_log supports the {Color text} inline highlight syntax" {
    run bash -c 'zz_log i "{Purple special} rest" 2>&1'
    [[ "$output" == *"special"* ]]
    [[ "$output" == *"rest"* ]]
}

@test "zz_log an unknown level falls back to printing the level string itself" {
    run bash -c 'zz_log ZZZ "custom" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ZZZ"* ]]
    [[ "$output" == *"custom"* ]]
}

@test "zz_log notice level prepends ::notice:: when GITHUB_ACTIONS=true" {
    run bash -c 'GITHUB_ACTIONS=true zz_log n "heads up" 2>&1'
    [[ "$output" == *"::notice::heads up"* ]]
}

@test "zz_log error level prepends ::error:: when GITHUB_ACTIONS=true" {
    run bash -c 'GITHUB_ACTIONS=true zz_log e "boom" 2>&1'
    [[ "$output" == *"::error::boom"* ]]
    [[ "$output" == *"✕"* ]]
}

@test "zz_log warning level prepends ::warning:: when GITHUB_ACTIONS=true" {
    run bash -c 'GITHUB_ACTIONS=true zz_log w "careful" 2>&1'
    [[ "$output" == *"::warning::careful"* ]]
    [[ "$output" == *"!"* ]]
}

@test "zz_log notice/error/warning do not add ::notice::/::error::/::warning:: outside GitHub Actions" {
    run bash -c 'unset GITHUB_ACTIONS; zz_log n "heads up" 2>&1'
    [[ "$output" != *"::notice::"* ]]
    run bash -c 'unset GITHUB_ACTIONS; zz_log e "boom" 2>&1'
    [[ "$output" != *"::error::"* ]]
    run bash -c 'unset GITHUB_ACTIONS; zz_log w "careful" 2>&1'
    [[ "$output" != *"::warning::"* ]]
}

@test "zz_log info/success levels never add ::error::/::warning:: even when GITHUB_ACTIONS=true" {
    run bash -c 'GITHUB_ACTIONS=true zz_log i "hi" 2>&1'
    [[ "$output" != *"::"* ]]
    run bash -c 'GITHUB_ACTIONS=true zz_log s "done" 2>&1'
    [[ "$output" != *"::"* ]]
}

@test "zz_log GHA annotation line strips {Color text} markup to plain text" {
    run bash -c 'GITHUB_ACTIONS=true zz_log e "{Purple special} rest" 2>&1'
    [[ "$output" == *"::error::special rest"* ]]
}

@test "zz_log GHA annotation line percent-escapes %, CR, and LF" {
    run bash -c 'GITHUB_ACTIONS=true zz_log e $'"'"'100% done\rline1\nline2'"'"' 2>&1'
    [[ "$output" == *"::error::100%25 done%0Dline1%0Aline2"* ]]
}
