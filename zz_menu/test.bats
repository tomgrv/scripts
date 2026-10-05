#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_menu is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_menu)"
    [ "$status" -eq 0 ]
}

@test "zz_menu prints the key of the chosen item" {
    run bash -c 'echo "2" | zz_menu "a=Alpha" "b=Beta" "c=Gamma" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz_menu uses the label as the key when an item has no '='" {
    run bash -c 'echo "1" | zz_menu "Alpha" "Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "Alpha" ]
}

@test "zz_menu only splits a key off at the first '='" {
    run bash -c 'echo "1" | zz_menu "a=x=y" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "a" ]
}

@test "zz_menu accepts a number with leading zeros" {
    run bash -c 'echo "02" | zz_menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz_menu exits 2 with no output on a bare Enter and no default" {
    run bash -c 'echo "" | zz_menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 2 ]
    [ "$output" = "" ]
}

@test "zz_menu prints the default key on a bare Enter" {
    run bash -c 'echo "" | zz_menu -d b "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "b" ]
}

@test "zz_menu exits 1 on q" {
    run bash -c 'echo "q" | zz_menu "a=Alpha" 2>/dev/null'
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "zz_menu exits 1 when input ends instead of looping forever" {
    run bash -c 'zz_menu "a=Alpha" </dev/null 2>/dev/null'
    [ "$status" -eq 1 ]
}

@test "zz_menu re-prompts on non-numeric and out-of-range input" {
    run bash -c 'printf "x\n0\n9\n1\n" | zz_menu "a=Alpha" "b=Beta" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "a" ]
}

@test "zz_menu warns on invalid input" {
    run bash -c 'printf "x\n1\n" | zz_menu "a=Alpha" 2>&1 1>/dev/null'
    [[ "$output" == *"Invalid input"* ]]
}

@test "zz_menu draws title, numbered labels and footer on stderr, not stdout" {
    run bash -c 'echo "1" | zz_menu -t "My menu" -f "custom hint" "a=Alpha" "b=Beta" 2>&1 1>/dev/null'
    [[ "$output" == *"My menu"* ]]
    [[ "$output" == *"1"*"Alpha"* ]]
    [[ "$output" == *"2"*"Beta"* ]]
    [[ "$output" == *"custom hint"* ]]
}

@test "zz_menu marks the default item" {
    run bash -c 'echo "" | zz_menu -d b "a=Alpha" "b=Beta" 2>&1 1>/dev/null'
    [[ "$output" == *"*Beta"* ]]
}

@test "zz_menu fails when given no items" {
    run bash -c 'echo "1" | zz_menu 2>/dev/null'
    [ "$status" -eq 1 ]
}

@test "zz_menu keeps labels with shell metacharacters intact" {
    run bash -c 'echo "1" | zz_menu "a=it'"'"'s \$HOME (ok)" 2>&1 1>/dev/null'
    [[ "$output" == *"it's \$HOME (ok)"* ]]
}
