#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    mkdir "$WORK/a"
    echo '{"name":"a","config":{"inputs":{"A_TOKEN":{"description":"tok","required":true,"secret":true},"A_OPT":{"default":"dflt"}}}}' >"$WORK/a/package.json"
    cd "$WORK"
}

teardown() {
    cd /
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-vars -S shows each input as set, required or optional" {
    run env A_OPT=x zz-vars -S -f "$WORK/env" a=a
    [ "$status" -eq 0 ]
    [[ "$output" == *"A_TOKEN"*"[required]"* ]]
    [[ "$output" == *"A_OPT"*"[set]"* ]]
}

@test "zz-vars -S reads the env file for what the environment lacks" {
    echo 'A_TOKEN=s3' >"$WORK/env"
    run zz-vars -S -f "$WORK/env" a=a
    [[ "$output" == *"A_TOKEN"*"[set]"* ]]
}

@test "zz-vars fails on a required input that is still empty" {
    run zz-vars -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"A_TOKEN is required by 'a'"* ]]
}

@test "zz-vars prints export lines for the resolved inputs" {
    run env A_TOKEN=t zz-vars -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"A_OPT"* && "$output" == *"dflt"* ]]
}

@test "zz-vars without an env file prints usage" {
    run zz-vars a=a
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "zz-vars treats config.ports as <NAME>_PORT inputs defaulting to the port" {
    mkdir "$WORK/p"
    echo '{"name":"p","config":{"ports":[{"name":"web_http","port":8080,"access":"private"}]}}' >"$WORK/p/package.json"
    run zz-vars -S -f "$WORK/env" p=p
    [[ "$output" == *"WEB_HTTP_PORT"*"[optional]"* ]]
    run zz-vars -f "$WORK/env" p=p </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"WEB_HTTP_PORT"*"8080"* ]]
    run env WEB_HTTP_PORT=9090 zz-vars -f "$WORK/env" p=p </dev/null
    [[ "$output" == *"9090"* ]]
}

@test "zz-vars rejects an input name that is not a shell identifier" {
    mkdir "$WORK/bad"
    echo '{"name":"bad","config":{"inputs":{"X;touch pwned":{}}}}' >"$WORK/bad/package.json"
    run zz-vars -f "$WORK/env" bad=bad </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid input name"* ]]
    [ ! -e pwned ]
}

@test "zz-vars -n falls back to the default, persists nothing and does not enforce required" {
    run zz-vars -n -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"export A_OPT='dflt'"* ]]
    [ ! -f "$WORK/env" ]
}

@test "zz-vars -a asks each unset input on stdin and persists the answer" {
    echo '{"name":"c","config":{"inputs":{"C_HOST":{"description":"Host?","default":"localhost"}}}}' >"$WORK/a/package.json"
    run bash -c "printf 'myhost\n' | zz-vars -a -f '$WORK/env' a=a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export C_HOST='myhost'"* ]]
    grep -q '^C_HOST=myhost$' "$WORK/env"
}

@test "zz-vars -e persists the values already set in the environment" {
    run env A_TOKEN=t zz-vars -e -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 0 ]
    grep -qx 'A_TOKEN=t' "$WORK/env"
}

@test "zz-vars prints an input under its name and its 'as' alias" {
    echo '{"name":"c","config":{"inputs":{"DB_PASSWORD":{"default":"pw","as":"PGPASSWORD"}}}}' >"$WORK/a/package.json"
    run zz-vars -n -f "$WORK/env" a=a
    [[ "$output" == *"export DB_PASSWORD='pw'"* && "$output" == *"export PGPASSWORD='pw'"* ]]
}

@test "zz-vars config.output filters what is printed" {
    echo '{"name":"c","config":{"inputs":{"X":{"default":"1"},"Y":{"default":"2"}},"output":[{"var":"X"}]}}' >"$WORK/a/package.json"
    run zz-vars -n -f "$WORK/env" a=a
    [[ "$output" == *"export X='1'"* && "$output" != *"export Y="* ]]
}

@test "zz-vars reads the deprecated config.input array and warns" {
    echo '{"name":"c","config":{"input":[{"var":"OLD","question":"Old?","default":"o"}]}}' >"$WORK/a/package.json"
    run zz-vars -n -f "$WORK/env" a=a
    [[ "$output" == *"export OLD='o'"* && "$output" == *"deprecated"* ]]
}

# menu_run <answers...>: run zz-vars -m with the answers scripted through ZZ_PROMPT_ANSWERS
# (an empty answer is a bare Enter).
menu_run() {
    printf '%s\n' "$@" >"$WORK/answers"
    ZZ_PROMPT_ANSWERS="$WORK/answers" zz-vars -m -f "$WORK/env" a=a >/dev/null 2>&1 || true
}

@test "zz-vars menu: a saved value can be deleted (a secret after a confirmation)" {
    printf 'A_TOKEN=s3\nA_OPT=keep\n' >"$WORK/env"
    chmod 600 "$WORK/env"
    menu_run 3 1 y ''
    ! grep -q '^A_TOKEN=' "$WORK/env"
    grep -q '^A_OPT=keep$' "$WORK/env"
}

@test "zz-vars menu: nothing is deleted when the secret's confirmation is refused" {
    printf 'A_TOKEN=s3\n' >"$WORK/env"
    chmod 600 "$WORK/env"
    menu_run 3 1 n ''
    grep -q '^A_TOKEN=s3$' "$WORK/env"
}

@test "zz-vars menu: q leaves the menu and proceeds, it does not abort" {
    printf 'A_TOKEN=s3\n' >"$WORK/env"
    chmod 600 "$WORK/env"
    printf 'q\n' >"$WORK/answers"
    run env ZZ_PROMPT_ANSWERS="$WORK/answers" zz-vars -m -f "$WORK/env" a=a
    [ "$status" -eq 0 ]
    [[ "$output" == *"A_TOKEN"* ]]
}

@test "zz-vars -S shows where each value comes from (env, env* when it overrides a saved value, file, default)" {
    echo 'A_TOKEN=saved' >"$WORK/env"
    run env A_TOKEN=other zz-vars -S -f "$WORK/env" a=a
    [[ "$output" == *"A_TOKEN"*"[set]"*"env*"* ]]
    [[ "$output" == *"A_OPT"*"default"* ]] || [[ "$output" == *"A_OPT"*"-"* ]]
    run zz-vars -S -f "$WORK/env" a=a
    [[ "$output" == *"A_TOKEN"*"[set]"*"file"* ]]
    run env A_TOKEN=saved zz-vars -S -f "$WORK/env" a=a
    [[ "$output" == *"A_TOKEN"*"[set]"*"env "* ]]
}
