#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-menu is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-menu)"
    [ "$status" -eq 0 ]
}

@test "zz-menu prints the key of the chosen item" {
    run bash -c 'echo "2" | zz-menu "a=Alpha" "b=Beta" "c=Gamma" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz-menu uses the label as the key when an item has no '='" {
    run bash -c 'echo "1" | zz-menu "Alpha" "Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "Alpha" ]
}

@test "zz-menu only splits a key off at the first '='" {
    run bash -c 'echo "1" | zz-menu "a=x=y" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "a" ]
}

@test "zz-menu accepts a number with leading zeros" {
    run bash -c 'echo "02" | zz-menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz-menu exits 2 with no output on a bare Enter and no default" {
    run bash -c 'echo "" | zz-menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 2 ]
    [ "$output" = "" ]
}

@test "zz-menu prints the default key on a bare Enter" {
    run bash -c 'echo "" | zz-menu -d b "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz-menu exits 1 on q" {
    run bash -c 'echo "q" | zz-menu "a=Alpha" 2>/dev/null'
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "zz-menu exits 1 when input ends instead of looping forever" {
    run bash -c 'zz-menu "a=Alpha" </dev/null 2>/dev/null'
    [ "$status" -eq 1 ]
}

@test "zz-menu re-prompts on non-numeric and out-of-range input" {
    run bash -c 'printf "x\n0\n9\n1\n" | zz-menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "a" ]
}

@test "zz-menu warns on invalid input" {
    run bash -c 'printf "x\n1\n" | zz-menu "a=Alpha" 2>&1 1>/dev/null'
    [[ "$output" == *"Invalid input"* ]]
}

@test "zz-menu draws title, numbered labels and footer on stderr, not stdout" {
    run bash -c 'echo "1" | zz-menu -t "My menu" -f "custom hint" "a=Alpha" "b=Beta" 2>&1 1>/dev/null'
    [[ "$output" == *"My menu"* ]]
    [[ "$output" == *"1"*"Alpha"* ]]
    [[ "$output" == *"2"*"Beta"* ]]
    [[ "$output" == *"custom hint"* ]]
}

@test "zz-menu marks the default item" {
    run bash -c 'echo "" | zz-menu -d b "a=Alpha" "b=Beta" 2>&1 1>/dev/null'
    [[ "$output" == *"*Beta"* ]]
}

@test "zz-menu fails when given no items" {
    run bash -c 'echo "1" | zz-menu 2>/dev/null'
    [ "$status" -eq 1 ]
}

@test "zz-menu keeps labels with shell metacharacters intact" {
    run bash -c 'echo "1" | zz-menu "a=it'"'"'s \$HOME (ok)" 2>&1 1>/dev/null'
    [[ "$output" == *"it's \$HOME (ok)"* ]]
}

@test "zz-menu -f renders a multi-line footer from \\n escapes" {
    run bash -c 'echo "1" | zz-menu -f "line one\nline two" "a=Alpha" 2>&1 1>/dev/null'
    [[ "$output" == *$'line one\nline two'* ]]
}

@test "zz-menu -c prints every item's key=state on Enter, starting at the first state" {
    run bash -c 'echo "" | zz-menu -c "skip,up,down" "a=Alpha" "b:up=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = $'a=skip\nb=up' ]
}

@test "zz-menu -c advances the chosen item to its next state and wraps around" {
    run bash -c 'printf "1\n1\n2\n2\n2\n2\n\n" | zz-menu -c "skip,up,down" "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    # a: skip -> up -> down; b: skip -> up -> down -> skip -> up
    [ "$output" = $'a=down\nb=up' ]
}

@test "zz-menu -c shows each item's state and redraws after a change" {
    run bash -c 'printf "1\n\n" | zz-menu -c "skip,up" "a=Alpha" 2>&1 1>/dev/null'
    [[ "$output" == *"[skip] Alpha"* ]]
    [[ "$output" == *"[up  ] Alpha"* ]]
}

@test "zz-menu -c exits 1 on q and prints nothing" {
    run bash -c 'printf "1\nq\n" | zz-menu -c "skip,up" "a=Alpha" 2>/dev/null'
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "zz-menu -c re-prompts on out-of-range input without changing any state" {
    run bash -c 'printf "5\n\n" | zz-menu -c "skip,up" "a=Alpha" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "a=skip" ]
}

@test "zz-menu -c keeps hyphenated keys intact" {
    run bash -c 'echo "" | zz-menu -c "skip,up" "vps-k3s:up=k3s" 2>/dev/null'
    [ "$output" = "vps-k3s=up" ]
}

@test "zz-menu keeps runs of spaces in labels (column alignment)" {
    run bash -c 'echo "1" | zz-menu "a=one   two    three" 2>&1 1>/dev/null'
    [[ "$output" == *"one   two    three"* ]]
}

@test "zz-menu prints titles and labels verbatim, without expanding backslash escapes" {
    run bash -c 'echo "1" | zz-menu -t "C:\new\c" "a=dir\tx\c done" 2>&1 1>/dev/null'
    [[ "$output" == *'C:\new\c'* ]]
    [[ "$output" == *'dir\tx\c done'* ]]
}
