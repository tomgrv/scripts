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
