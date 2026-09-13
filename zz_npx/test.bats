#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_npx is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_npx)"
    [ "$status" -eq 0 ]
}

@test "zz_npx requires a tool argument" {
    run zz_npx
    [ "$status" -ne 0 ]
}

@test "zz_npx runs a locally installed node_modules/.bin binary directly, without touching npx" {
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho local-ran "$@"\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env INIT_CWD="$proj" PATH="$PATH:/nonexistent" zz_npx mytool a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"local-ran a b"* ]]
    rm -rf "$proj"
}

@test "zz_npx uses PWD (not the shell's cwd) fallback when INIT_CWD is unset" {
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho found-via-pwd\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env -u INIT_CWD bash -c "cd '$proj' && PWD='$proj' zz_npx mytool"
    [ "$status" -eq 0 ]
    [[ "$output" == *"found-via-pwd"* ]]
    rm -rf "$proj"
}

@test "zz_npx errors clearly when the tool is neither local nor npx is available" {
    proj=$(mktemp -d)
    # A toolbox with just what zz_npx/zz_colors/zz_args need, and no npx.
    toolbox=$(mktemp -d)
    for tool in sh sed grep cut tr expr basename dirname printf getopts; do
        bin=$(command -v "$tool" 2>/dev/null) && ln -s "$bin" "$toolbox/$tool"
    done
    zz_npx_bin=$(command -v zz_npx)
    ln -s "$zz_npx_bin" "$toolbox/zz_npx"
    ln -s "$(command -v zz_colors)" "$toolbox/zz_colors"
    ln -s "$(command -v zz_args)" "$toolbox/zz_args"
    run env INIT_CWD="$proj" PATH="$toolbox" zz_npx notatool
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* || "$output" == *"Cannot run"* ]]
    rm -rf "$proj" "$toolbox"
}

@test "zz_npx passes remaining arguments through to the local binary" {
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\nfor a in "$@"; do echo "arg:$a"; done\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env INIT_CWD="$proj" zz_npx mytool one two three
    [ "$status" -eq 0 ]
    [[ "$output" == *"arg:one"* ]]
    [[ "$output" == *"arg:two"* ]]
    [[ "$output" == *"arg:three"* ]]
    rm -rf "$proj"
}

@test "zz_npx does not re-pass the tool name as a leftover argument when none are given" {
    # Regression: zz_args used to only clear its caller's "$@" (via "set
    # --") when at least one argument remained after earlier positionals
    # consumed their share. With exactly one argument ("mytool") and
    # nothing left over, that left zz_npx's *original* "$@" (still
    # "mytool") untouched, so the binary was invoked with "mytool" as both
    # $tool and a stray extra argument -- exactly the "Unknown argument:
    # commitlint" failure this reproduces for a real npm CLI's arg parser.
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho "argc:$#"\nfor a in "$@"; do echo "arg:$a"; done\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env INIT_CWD="$proj" zz_npx mytool
    [ "$status" -eq 0 ]
    [[ "$output" == *"argc:0"* ]]
    [[ "$output" != *"arg:"* ]]
    rm -rf "$proj"
}

@test "zz_npx commitlint present case: piped stdin, no extra args, tool not duplicated" {
    # The exact real-world case that surfaced the bug: check-pr-format
    # runs `echo "${formatted_title}" | zz_npx commitlint 2>&1` -- stdin
    # piped in, "commitlint" the only argument. Pin this down verbatim
    # (not just the generic "mytool" case above) so a future regression
    # here is caught under the same name and shape as the original CI
    # failure ("Unknown argument: commitlint").
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho "argc:$#"\nfor a in "$@"; do echo "arg:$a"; done\ncat\n' >"$proj/node_modules/.bin/commitlint"
    chmod +x "$proj/node_modules/.bin/commitlint"
    run bash -c 'echo "feat: title" | INIT_CWD="'"$proj"'" zz_npx commitlint'
    [ "$status" -eq 0 ]
    [[ "$output" == *"argc:0"* ]]
    [[ "$output" != *"arg:"* ]]
    [[ "$output" == *"feat: title"* ]]
    rm -rf "$proj"
}

@test "zz_npx passes an argument containing shell metacharacters through unmangled" {
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho "$2"\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env INIT_CWD="$proj" zz_npx mytool --text "fix(scope): \$(danger) \`danger\`"
    [ "$status" -eq 0 ]
    [[ "$output" == *'fix(scope): $(danger) `danger`'* ]]
    rm -rf "$proj"
}

@test "zz_npx -s flag is accepted (allow-lifecycle-scripts option, doesn't affect the local-binary fast path)" {
    proj=$(mktemp -d)
    mkdir -p "$proj/node_modules/.bin"
    printf '#!/bin/sh\necho local-ran-with-s\n' >"$proj/node_modules/.bin/mytool"
    chmod +x "$proj/node_modules/.bin/mytool"
    run env INIT_CWD="$proj" zz_npx -s mytool
    [ "$status" -eq 0 ]
    [[ "$output" == *"local-ran-with-s"* ]]
    rm -rf "$proj"
}
