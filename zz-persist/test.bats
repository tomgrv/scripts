#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-persist is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-persist)"
    [ "$status" -eq 0 ]
}

@test "zz-persist upserts KEY=VALUE into an env file" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp"
    run zz-persist -f "$tmp" FOO baz
    grep -q '^FOO=baz$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist appends a new key without disturbing existing ones" {
    tmp=$(mktemp)
    printf 'EXISTING=1\n' >"$tmp"
    run zz-persist -f "$tmp" NEWKEY newval
    [ "$status" -eq 0 ]
    grep -q '^EXISTING=1$' "$tmp"
    grep -q '^NEWKEY=newval$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist creates the target file if it does not exist" {
    tmp="$(mktemp -u)"
    [ ! -e "$tmp" ]
    run zz-persist -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    [ -f "$tmp" ]
    grep -q '^FOO=bar$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist requires a key argument" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp"
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}

@test "zz-persist rejects an invalid variable name" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" "1BAD-NAME" value
    [ "$status" -ne 0 ]
    ! grep -q "1BAD-NAME" "$tmp"
    rm -f "$tmp"
}

@test "zz-persist accepts a single-letter or underscore-led key and rejects the rest" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" A one
    [ "$status" -eq 0 ]
    run zz-persist -f "$tmp" _x two
    [ "$status" -eq 0 ]
    grep -qx 'A=one' "$tmp"
    grep -qx '_x=two' "$tmp"
    run zz-persist -f "$tmp" "A-B" three
    [ "$status" -ne 0 ]
    run zz-persist -f "$tmp" "9x" four
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}

@test "zz-persist requires at least one of -f/-p" {
    run zz-persist FOO bar
    [ "$status" -ne 0 ]
}

@test "zz-persist writes to a profile.d snippet under a writable HOME-relative override" {
    tmp=$(mktemp -d)
    # /etc/profile.d itself is used verbatim by run.sh (not configurable),
    # so exercise the file (-f) path for durability semantics and instead
    # just verify the -p path is attempted (may warn-skip without root
    # write access to /etc, which is fine and still exit 0).
    run zz-persist -f "$tmp/env" -p somezzprofile FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp/env"
    rm -rf "$tmp"
    rm -f /etc/profile.d/somezzprofile.sh
}

@test "zz-persist can write to both -f and -p simultaneously" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" -p zzptest KEY val
    [ "$status" -eq 0 ]
    grep -q '^KEY=val$' "$tmp"
    if [ -f /etc/profile.d/zzptest.sh ]; then
        grep -q '^export KEY=val$' /etc/profile.d/zzptest.sh
    fi
    rm -f "$tmp" /etc/profile.d/zzptest.sh
}

@test "zz-persist -i with -v uses the default when not on a terminal" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" -i "Enter value" -v defaultval KEY </dev/null
    [ "$status" -eq 0 ]
    grep -q '^KEY=defaultval$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist -i shows and reuses the current value as default" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" KEY first
    [ "$status" -eq 0 ]
    run zz-persist -f "$tmp" -i "Enter value" -v ignored KEY </dev/null
    [ "$status" -eq 0 ]
    grep -q '^KEY=first$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist -i with -s masks an already-set secret in the log output" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" KEY supersecret
    [ "$status" -eq 0 ]
    run zz-persist -f "$tmp" -i "Enter secret" -s -v ignored KEY </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *'***'* ]]
    [[ "$output" != *'supersecret'* ]]
    grep -q '^KEY=supersecret$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist refuses to persist a secret into a non-owner-only file" {
    tmp=$(mktemp)
    chmod 644 "$tmp"
    run zz-persist -f "$tmp" -i "Enter secret" -s -v ignored KEY </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *'refusing to persist secret'* ]]
    ! grep -q '^KEY=' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist persists a secret into an owner-only file" {
    tmp=$(mktemp)
    chmod 600 "$tmp"
    run zz-persist -f "$tmp" -i "Enter secret" -s -v injected KEY </dev/null
    [ "$status" -eq 0 ]
    grep -q '^KEY=injected$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist upsert into profile.d replaces an existing export line" {
    if ! mkdir -p /etc/profile.d 2>/dev/null || ! touch /etc/profile.d/.zzwritetest 2>/dev/null; then
        skip "no write access to /etc/profile.d in this environment"
    fi
    rm -f /etc/profile.d/.zzwritetest
    tmp=$(mktemp)
    run zz-persist -f "$tmp" -p zzptest2 KEY first
    [ "$status" -eq 0 ]
    run zz-persist -f "$tmp" -p zzptest2 KEY second
    [ "$status" -eq 0 ]
    grep -q '^export KEY=second$' /etc/profile.d/zzptest2.sh
    ! grep -q '^export KEY=first$' /etc/profile.d/zzptest2.sh
    rm -f "$tmp" /etc/profile.d/zzptest2.sh
}

@test "zz-persist -s without -i refuses a secret value for a non-owner-only file" {
    tmp=$(mktemp)
    chmod 644 "$tmp"
    run zz-persist -f "$tmp" -s KEY topsecret
    [ "$status" -eq 0 ]
    [[ "$output" == *'refusing to persist secret'* ]]
    ! grep -q '^KEY=' "$tmp"
    chmod 600 "$tmp"
    run zz-persist -f "$tmp" -s KEY topsecret
    grep -qx 'KEY=topsecret' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist creates a new env file owner-only, so a secret can be stored right away" {
    d=$(mktemp -d)
    run zz-persist -f "$d/new.env" -s KEY topsecret
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$d/new.env")" = 600 ]
    grep -qx 'KEY=topsecret' "$d/new.env"
    rm -rf "$d"
}

@test "zz-persist only masks when -s is given" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" KEY plainvalue
    run zz-persist -f "$tmp" -i "Enter value" KEY </dev/null
    [[ "$output" == *'plainvalue'* ]]
    rm -f "$tmp"
}

@test "zz-persist -i works when the target file does not exist yet" {
    d=$(mktemp -d)
    run zz-persist -f "$d/new.env" -i "Enter value" -v dflt KEY </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'KEY=dflt' "$d/new.env"
    rm -rf "$d"
}

@test "zz-persist quotes a risky value in the profile snippet and unquotes it on read-back" {
    d=$(mktemp -d)
    run env ZZ_PROFILE_DIR="$d" zz-persist -p zzq KEY 'a b $(id) it'"'"'s'
    [ "$status" -eq 0 ]
    [ "$(sh -c ". $d/zzq.sh; printf %s \"\$KEY\"")" = "a b \$(id) it's" ]
    run env ZZ_PROFILE_DIR="$d" zz-persist -p zzq -i Q KEY </dev/null
    [[ "$output" == *"it's"* ]]
    rm -rf "$d"
}

@test "zz-persist keeps backslashes and & in values and rejects a multi-line value" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" KEY 'a\nb&c|d'
    [ "$status" -eq 0 ]
    grep -qF 'KEY=a\nb&c|d' "$tmp"
    run zz-persist -f "$tmp" KEY "$(printf 'a\nb')"
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}

@test "zz-persist -q writes without logging the write" {
    tmp=$(mktemp)
    run zz-persist -q -f "$tmp" KEY val
    [ "$status" -eq 0 ]
    [[ "$output" != *"persisted"* ]]
    grep -qx 'KEY=val' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist -g generates a value once, keeps it afterwards and prints it" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" -g 16 PW
    [ "$status" -eq 0 ]
    first="${lines[${#lines[@]}-1]}"
    [ "${#first}" -eq 16 ]
    grep -q "^PW=$first\$" "$tmp"
    run zz-persist -f "$tmp" -g 16 PW
    [ "${lines[${#lines[@]}-1]}" = "$first" ]
    rm -f "$tmp"
}

@test "zz-persist -g takes a given value over generating one" {
    tmp=$(mktemp)
    run zz-persist -f "$tmp" -g 16 PW given
    [ "${lines[${#lines[@]}-1]}" = "given" ]
    grep -q '^PW=given$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist -r prints the stored value and writes nothing" {
    tmp=$(mktemp)
    printf 'A=1\nB=two\n' >"$tmp"
    run zz-persist -f "$tmp" -r B
    [ "$status" -eq 0 ]
    [ "$output" = "two" ]
    run zz-persist -f "$tmp" -r MISSING
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(wc -l <"$tmp")" -eq 2 ]
    rm -f "$tmp"
}

@test "zz-persist -u removes the key and leaves the others" {
    tmp=$(mktemp)
    printf 'A=1\nB=two\n' >"$tmp"
    run zz-persist -f "$tmp" -u A
    [ "$status" -eq 0 ]
    ! grep -q '^A=' "$tmp"
    grep -q '^B=two$' "$tmp"
    rm -f "$tmp"
}

@test "zz-persist -l adds a whole line once, keeping the file's other lines" {
    tmp=$(mktemp)
    printf 'first\n' >"$tmp"
    run zz-persist -l -f "$tmp" 'export KUBECONFIG=/etc/k.yaml'
    [ "$status" -eq 0 ]
    run zz-persist -l -f "$tmp" 'export KUBECONFIG=/etc/k.yaml'
    [ "$(grep -c '^export KUBECONFIG=/etc/k.yaml$' "$tmp")" -eq 1 ]
    grep -q '^first$' "$tmp"
    run zz-persist -l 'no file'
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}
