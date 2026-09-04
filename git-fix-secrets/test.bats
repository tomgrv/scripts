#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q -b main
    git config user.email a@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-fix-secrets is installed on PATH and syntactically valid" {
    command -v git-fix-secrets
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-secrets -h prints usage and exits non-zero" {
    run git-fix-secrets -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Redact a secret"* ]]
}

@test "git-fix-secrets fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-secrets -g "*.env" -s "x" </dev/null
    [ "$status" -ne 0 ]
}

@test "git-fix-secrets requires a glob pattern" {
    echo one > f && git add f && git commit -qm "c1"
    run git-fix-secrets -s "somesecret" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"glob pattern is required"* ]]
}

@test "git-fix-secrets requires a secret value" {
    echo one > f && git add f && git commit -qm "c1"
    run git-fix-secrets -g "*.env" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"secret value is required"* ]]
}

@test "git-fix-secrets refuses to run with uncommitted changes" {
    echo one > f && git add f && git commit -qm "c1"
    echo dirty >> f
    run git-fix-secrets -g "*.env" -s "x" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "git-fix-secrets reports no occurrences when the secret is absent" {
    printf 'API_KEY=notthesecret\n' > .env
    git add .env && git commit -qm "add env"

    run git-fix-secrets -g "*.env" -s "supersecret123" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"No occurrences"* ]]
    [ "$(cat .env)" = "API_KEY=notthesecret" ]
}

@test "git-fix-secrets dry-run lists matches without modifying anything" {
    printf 'API_KEY=supersecret123\n' > .env
    git add .env && git commit -qm "add env"

    run git-fix-secrets -d -g "*.env" -s "supersecret123" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *"Dry run complete"* ]]
    [ "$(cat .env)" = "API_KEY=supersecret123" ]
}

@test "git-fix-secrets redacts a planted secret from tracked file content across history" {
    printf 'API_KEY=supersecret123\n' > .env
    git add .env && git commit -qm "add env"

    run bash -c 'echo y | git-fix-secrets -g "*.env" -s "supersecret123" -r "REDACTED"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Secret replaced"* ]]

    [ "$(cat .env)" = "API_KEY=REDACTED" ]
    ! git log -p --all -- .env | grep -q "supersecret123"
}

@test "git-fix-secrets aborts the rewrite when the user declines" {
    printf 'API_KEY=supersecret123\n' > .env
    git add .env && git commit -qm "add env"
    sha=$(git rev-parse HEAD)

    run bash -c "echo n | git-fix-secrets -g '*.env' -s supersecret123 $sha"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cancelled by user"* ]]
    [ "$(cat .env)" = "API_KEY=supersecret123" ]
}

@test "git-fix-secrets also redacts the secret from commit messages with -m" {
    printf 'nothing secret here\n' > other.txt
    git add other.txt
    git commit -qm "commit mentioning supersecret123 in message"

    run bash -c 'echo y | git-fix-secrets -m -g "*.env" -s "supersecret123" -r "REDACTED"'
    [ "$status" -eq 0 ]

    run git log -1 --format=%s
    [[ "$output" == *"REDACTED"* ]]
    [[ "$output" != *"supersecret123"* ]]
}
