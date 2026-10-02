#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    cat >composer.json <<'JSON'
{"name":"app/core","extra":{"merge-plugin":{"include":["modules/*/composer.json","packages/*/*/composer.json"]}}}
JSON
    mkdir -p tests/Unit app modules/Blog/tests modules/Shop/tests packages/acme/lib/tests packages/acme/notests
    echo '{"name":"mod/blog","require":{"acme/lib":"*"}}' >modules/Blog/composer.json
    echo '{"name":"mod/shop"}' >modules/Shop/composer.json
    echo '{"name":"acme/lib"}' >packages/acme/lib/composer.json
    echo '{"name":"acme/notests"}' >packages/acme/notests/composer.json
    touch tests/Unit/a.php app/a.php modules/Blog/tests/t.php modules/Shop/tests/t.php packages/acme/lib/tests/t.php
    git add -A && git commit -qm init
    git checkout -qb feature
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

change() {
    echo x >>"$1"
    git add -A && git commit -qm change
}

@test "php-changed is on PATH and syntactically valid" {
    command -v php-changed
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "no change selects nothing" {
    run php-changed -b main
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "module change selects only that module" {
    change modules/Shop/tests/t.php
    run php-changed -b main
    [ "$output" = "modules/Shop" ]
}

@test "package change also selects dependent modules" {
    change packages/acme/lib/tests/t.php
    run php-changed -b main
    [ "$output" = "modules/Blog
packages/acme/lib" ]
}

@test "core test change selects core only" {
    change tests/Unit/a.php
    run php-changed -b main
    [ "$output" = "core" ]
}

@test "shared core change selects every part with tests" {
    change app/a.php
    run php-changed -b main
    [ "$output" = "core
modules/Blog
modules/Shop
packages/acme/lib" ]
}

@test "parts without tests are never listed" {
    touch packages/acme/notests/f.php
    change packages/acme/notests/f.php
    run php-changed -b main
    [ -z "$output" ]
}

@test "json format emits a matrix" {
    change modules/Shop/tests/t.php
    run php-changed -b main -f json
    [ "$output" = '[{"name":"modules/Shop","suite":"Shop","path":"modules/Shop/tests"}]' ]
}

@test "suites format maps core to Unit,Feature" {
    change tests/Unit/a.php
    run php-changed -b main -f suites
    [ "$output" = "Unit,Feature" ]
}

@test "-a selects everything regardless of the diff" {
    run php-changed -b main -a
    [[ "$output" == *"core"* ]]
    [[ "$output" == *"modules/Shop"* ]]
}
