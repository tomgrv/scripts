#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q .
    git config user.email t@t && git config user.name t
    mkdir lib app tool
    echo '{"name":"root","workspaces":["lib","app","tool"]}' >package.json
    echo '{"name":"@x/lib"}' >lib/package.json
    echo '{"name":"@x/app","peerDependencies":{"@x/lib":"*"}}' >app/package.json
    echo '{"name":"@x/tool","devDependencies":{"@x/app":"*"}}' >tool/package.json
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

impacted() { printf '%s\n' "$@" | ws-impacted; }

@test "ws-impacted is on PATH and syntactically valid" {
    run bash -n "$(command -v ws-impacted)"
    [ "$status" -eq 0 ]
}

@test "ws-impacted -h prints usage and exits non-zero" {
    run ws-impacted -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "a changed workspace is impacted together with its transitive dependents" {
    run impacted lib/run.sh
    [ "$status" -eq 0 ]
    [ "$output" = '(.location | IN("lib","app","tool"))' ]
}

@test "a leaf workspace impacts only itself" {
    run impacted tool/test.bats
    [ "$output" = '(.location | IN("tool"))' ]
}

@test "a middle workspace impacts itself and its dependents, not its dependencies" {
    run impacted app/run.sh
    [ "$output" = '(.location | IN("app","tool"))' ]
}

@test "a file owned by no workspace impacts everybody (empty filter)" {
    run impacted tool/run.sh .github/workflows/x.yml
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Markdown impacts nobody: a docs-only change gives a filter that keeps nothing" {
    run impacted README.md lib/README.md
    [ "$output" = "false" ]
}

@test "Markdown beside a code change does not widen the scope" {
    run impacted tool/run.sh README.md
    [ "$output" = '(.location | IN("tool"))' ]
}

@test "-r takes the changed files from a git range instead of stdin" {
    git add -A && git commit -q -m base
    echo x >lib/run.sh && git add -A && git commit -q -m change
    run ws-impacted -r HEAD~1..HEAD
    [ "$status" -eq 0 ]
    [ "$output" = '(.location | IN("lib","app","tool"))' ]
}

@test "the printed filter is a valid jq select() over a list-packages object" {
    run impacted app/run.sh
    filter="$output"
    run jq -c "[.[] | select($filter)] | map(.location)" <<<'[{"location":"lib"},{"location":"app"},{"location":"tool"}]'
    [ "$status" -eq 0 ]
    [ "$output" = '["app","tool"]' ]
}
