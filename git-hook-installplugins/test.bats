#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
    rm -f "$BATS_TEST_DIRNAME/PLUGINS"
}

@test "git-hook-installplugins is installed on PATH and syntactically valid" {
    command -v git-hook-installplugins
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-hook-installplugins -h prints usage and exits non-zero" {
    run git-hook-installplugins -h </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Install npm plugins"* ]]
}

@test "git-hook-installplugins errors when no json key is given" {
    echo '{}' >package.json
    run git-hook-installplugins </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"JSON key is required"* ]]
}

@test "git-hook-installplugins skips cleanly when no plugins are declared" {
    echo '{}' >package.json
    run git-hook-installplugins '.prettier.plugins//""'
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plugins found"* ]]
}

@test "git-hook-installplugins reports already-installed plugins without calling npm install" {
    echo '{"prettier":{"plugins":["prettier-plugin-sh"]}}' >package.json

    stub_script npm <<-'EOF'
	#!/bin/sh
	case "$1" in
	list) echo "prettier-plugin-sh@1.0.0" ;;
	install) echo "npm install should not run in this test" >&2; exit 1 ;;
	esac
	EOF

    run git-hook-installplugins '.prettier.plugins//""'
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}
