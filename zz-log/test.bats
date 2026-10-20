#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-log is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-log)"
    [ "$status" -eq 0 ]
}

@test "zz-log prints a leveled message to stderr" {
    run zz-log i "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "zz-log supports i/n/w/e/s/d/- levels without erroring" {
    for lvl in i n w e s d -; do
        run zz-log "$lvl" "msg"
        [ "$status" -eq 0 ]
    done
}

@test "zz-log debug (d) level is silent unless ZZ_DEBUG is set" {
    run bash -c 'unset ZZ_DEBUG; zz-log d "hidden" 2>&1'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c 'ZZ_DEBUG=1 zz-log d "shown" 2>&1'
    [[ "$output" == *"shown"* ]]
}

@test "zz-log writes to stderr, not stdout" {
    run bash -c 'zz-log i "onstderr" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c 'zz-log i "onstderr" 1>/dev/null'
    [[ "$output" == *"onstderr"* ]]
}

@test "zz-log info level uses the info pictogram/arrow" {
    run bash -c 'zz-log i "hi" 2>&1'
    [[ "$output" == *"→"* ]]
}

@test "zz-log notice level uses the notice (cyan) pictogram" {
    run bash -c 'unset GITHUB_ACTIONS; zz-log n "heads up" 2>&1'
    [[ "$output" == *$'\033[1;36m'* ]]
    [[ "$output" == *"heads up"* ]]
    [[ "$output" != *"✕"* ]]
    [[ "$output" != *"✔"* ]]
}

@test "zz-log warning level uses the warning pictogram" {
    run bash -c 'unset GITHUB_ACTIONS; zz-log w "careful" 2>&1'
    [[ "$output" == *"!"* ]]
    [[ "$output" == *"careful"* ]]
}

@test "zz-log error level uses the error pictogram" {
    run bash -c 'unset GITHUB_ACTIONS; zz-log e "boom" 2>&1'
    [[ "$output" == *"✕"* ]]
    [[ "$output" == *"boom"* ]]
}

@test "zz-log success level uses the success pictogram" {
    run bash -c 'zz-log s "done" 2>&1'
    [[ "$output" == *"✔"* ]]
    [[ "$output" == *"done"* ]]
}

@test "zz-log plain (-) level has no pictogram, just indentation" {
    run bash -c 'zz-log - "plainmsg" 2>&1'
    [[ "$output" == *"plainmsg"* ]]
    [[ "$output" != *"✕"* ]]
    [[ "$output" != *"✔"* ]]
}

@test "zz-log joins multiple message words with spaces" {
    run bash -c 'zz-log i one two three 2>&1'
    [[ "$output" == *"one two three"* ]]
}

@test "zz-log supports the {Color text} inline highlight syntax" {
    run bash -c 'zz-log i "{Purple special} rest" 2>&1'
    [[ "$output" == *"special"* ]]
    [[ "$output" == *"rest"* ]]
}

@test "zz-log an unknown level falls back to printing the level string itself" {
    run bash -c 'zz-log ZZZ "custom" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ZZZ"* ]]
    [[ "$output" == *"custom"* ]]
}

@test "zz-log notice level emits only the ::notice:: annotation when GITHUB_ACTIONS=true, not the colored line too" {
    run bash -c 'GITHUB_ACTIONS=true zz-log n "heads up" 2>&1'
    [[ "$output" == *"::notice::heads up"* ]]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "zz-log error level emits only the ::error:: annotation when GITHUB_ACTIONS=true, not the colored line too" {
    run bash -c 'GITHUB_ACTIONS=true zz-log e "boom" 2>&1'
    [[ "$output" == *"::error::boom"* ]]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "zz-log warning level emits only the ::warning:: annotation when GITHUB_ACTIONS=true, not the colored line too" {
    run bash -c 'GITHUB_ACTIONS=true zz-log w "careful" 2>&1'
    [[ "$output" == *"::warning::careful"* ]]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "zz-log notice/error/warning do not add ::notice::/::error::/::warning:: outside GitHub Actions" {
    run bash -c 'unset GITHUB_ACTIONS; zz-log n "heads up" 2>&1'
    [[ "$output" != *"::notice::"* ]]
    run bash -c 'unset GITHUB_ACTIONS; zz-log e "boom" 2>&1'
    [[ "$output" != *"::error::"* ]]
    run bash -c 'unset GITHUB_ACTIONS; zz-log w "careful" 2>&1'
    [[ "$output" != *"::warning::"* ]]
}

@test "zz-log info/success levels never add ::error::/::warning:: even when GITHUB_ACTIONS=true" {
    run bash -c 'GITHUB_ACTIONS=true zz-log i "hi" 2>&1'
    [[ "$output" != *"::"* ]]
    run bash -c 'GITHUB_ACTIONS=true zz-log s "done" 2>&1'
    [[ "$output" != *"::"* ]]
}

@test "zz-log GHA annotation line strips {Color text} markup to plain text" {
    run bash -c 'GITHUB_ACTIONS=true zz-log e "{Purple special} rest" 2>&1'
    [[ "$output" == *"::error::special rest"* ]]
}

@test "zz-log GHA annotation line percent-escapes %, CR, and LF" {
    run bash -c 'GITHUB_ACTIONS=true zz-log e $'"'"'100% done\rline1\nline2'"'"' 2>&1'
    [[ "$output" == *"::error::100%25 done%0Dline1%0Aline2"* ]]
}

@test "zz-log prints shell-special characters (\" \$ \` parentheses) verbatim" {
    run bash -c 'zz-log i '"'"'select(.path | test("(^|/)src/")) $HOME `id`'"'"' 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *'select(.path | test("(^|/)src/")) $HOME `id`'* ]]
}

@test "zz-log tags script lines with ZZ_LOG_STEP; headline levels ignore ZZ_LOG_INDENT" {
    run bash -c 'ZZ_LOG_STEP=fetch ZZ_LOG_INDENT=4 zz-log i "hi" 2>&1 | sed "s/\x1b\[[0-9;]*m//g"'
    [ "$output" = "→ [fetch] hi" ]
}

@test "zz-log o dims stdin lines behind a gutter, without step tag" {
    run bash -c 'printf "a\nb\n" | ZZ_LOG_STEP=fetch zz-log o 2>&1'
    [[ "$output" == *"│ a"* && "$output" == *"│ b"* ]]
    [[ "$output" != *"[fetch]"* ]]
}

@test "zz-log leaves a brace that is not a colour marker alone" {
    run bash -c 'zz-log i "{\"a\": 1} {Red x} {" 2>&1'
    [[ "$output" == *"{\"a\": 1}"* && "$output" == *"x"* && "$output" == *"{"* ]]
}

@test "zz-log prints a command substitution in the message instead of running it" {
    run bash -c 'zz-log i "\$(echo pwned)" 2>&1'
    [[ "$output" == *'$(echo pwned)'* ]]
}

@test "zz-log custom level is the caller's own prefix: no step tag, no ZZ_LOG_INDENT" {
    run bash -c 'ZZ_LOG_STEP=fetch ZZ_LOG_INDENT=6 zz-log "  | -" "nested" 2>&1'
    [[ "$output" == "  | - nested"* ]]
    [[ "$output" != *"[fetch]"* ]]
}

@test "zz-log - is a plain detail line indented by ZZ_LOG_INDENT, without pictogram or step tag" {
    run bash -c 'ZZ_LOG_STEP=s ZZ_LOG_INDENT=4 zz-log - "detail" 2>&1 | sed "s/\x1b\[[0-9;]*m//g"'
    [ "$output" = "      detail" ]
}
