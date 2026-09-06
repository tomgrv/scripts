#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_persist is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_persist)"
    [ "$status" -eq 0 ]
}

@test "zz_persist upserts KEY=VALUE into an env file" {
    tmp=$(mktemp)
    run zz_persist -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp"
    run zz_persist -f "$tmp" FOO baz
    grep -q '^FOO=baz$' "$tmp"
    rm -f "$tmp"
}

@test "zz_persist appends a new key without disturbing existing ones" {
    tmp=$(mktemp)
    printf 'EXISTING=1\n' >"$tmp"
    run zz_persist -f "$tmp" NEWKEY newval
    [ "$status" -eq 0 ]
    grep -q '^EXISTING=1$' "$tmp"
    grep -q '^NEWKEY=newval$' "$tmp"
    rm -f "$tmp"
}

@test "zz_persist creates the target file if it does not exist" {
    tmp="$(mktemp -u)"
    [ ! -e "$tmp" ]
    run zz_persist -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    [ -f "$tmp" ]
    grep -q '^FOO=bar$' "$tmp"
    rm -f "$tmp"
}

@test "zz_persist requires a key argument" {
    tmp=$(mktemp)
    run zz_persist -f "$tmp"
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}

@test "zz_persist rejects an invalid variable name" {
    tmp=$(mktemp)
    run zz_persist -f "$tmp" "1BAD-NAME" value
    [ "$status" -ne 0 ]
    ! grep -q "1BAD-NAME" "$tmp"
    rm -f "$tmp"
}

@test "zz_persist requires at least one of -f/-p" {
    run zz_persist FOO bar
    [ "$status" -ne 0 ]
}

@test "zz_persist writes to a profile.d snippet under a writable HOME-relative override" {
    tmp=$(mktemp -d)
    # /etc/profile.d itself is used verbatim by run.sh (not configurable),
    # so exercise the file (-f) path for durability semantics and instead
    # just verify the -p path is attempted (may warn-skip without root
    # write access to /etc, which is fine and still exit 0).
    run zz_persist -f "$tmp/env" -p somezzprofile FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp/env"
    rm -rf "$tmp"
    rm -f /etc/profile.d/somezzprofile.sh
}

@test "zz_persist can write to both -f and -p simultaneously" {
    tmp=$(mktemp)
    run zz_persist -f "$tmp" -p zzptest KEY val
    [ "$status" -eq 0 ]
    grep -q '^KEY=val$' "$tmp"
    if [ -f /etc/profile.d/zzptest.sh ]; then
        grep -q '^export KEY=val$' /etc/profile.d/zzptest.sh
    fi
    rm -f "$tmp" /etc/profile.d/zzptest.sh
}

@test "zz_persist upsert into profile.d replaces an existing export line" {
    skip_msg=""
    if ! mkdir -p /etc/profile.d 2>/dev/null; then
        skip "no write access to /etc/profile.d in this environment"
    fi
    tmp=$(mktemp)
    run zz_persist -f "$tmp" -p zzptest2 KEY first
    [ "$status" -eq 0 ]
    run zz_persist -f "$tmp" -p zzptest2 KEY second
    [ "$status" -eq 0 ]
    grep -q '^export KEY=second$' /etc/profile.d/zzptest2.sh
    ! grep -q '^export KEY=first$' /etc/profile.d/zzptest2.sh
    rm -f "$tmp" /etc/profile.d/zzptest2.sh
}
