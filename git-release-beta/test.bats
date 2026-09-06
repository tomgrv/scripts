#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    # Stub external dependencies (GitVersion `gv` and git-flow) that
    # git-release-beta shells out to, so its own branch/state logic can be
    # exercised hermetically without either tool actually installed.
    cat >"$TEST_BIN/gv" <<'EOF'
#!/bin/sh
echo "${GBV_STUB:-1.2.3}"
EOF
    chmod +x "$TEST_BIN/gv"

    cat >"$TEST_BIN/git-flow" <<'EOF'
#!/bin/sh
sub=$1; shift
action=$1; shift
case "$sub-$action" in
    release-start)
        name=$1
        git checkout -qb "release/$name" develop
        ;;
esac
EOF
    chmod +x "$TEST_BIN/git-flow"

    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
    git config commit.gpgsign false
    git commit -q --allow-empty -m init
    git checkout -qb develop

    BARE=$(mktemp -d)/origin.git
    git init -q --bare "$BARE"
    git remote add origin "$BARE"
    git push -qu origin develop
}

teardown() {
    cd /
    rm -rf "$REPO" "$(dirname "$BARE")"
    teardown_scripts_path
}

@test "git-release-beta is installed on PATH and syntactically valid" {
    command -v git-release-beta
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "creates and pushes a release branch named after the computed version" {
    run git-release-beta
    [ "$status" -eq 0 ]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "release/1.2.3" ]
    [ "$(cat .git/RELEASE)" = "1.2.3" ]
    git --git-dir="$BARE" show-ref --verify --quiet refs/heads/release/1.2.3
}

@test "is idempotent: re-running resumes an already-created release branch" {
    git-release-beta
    run git-release-beta
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists, resuming"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "release/1.2.3" ]
}

@test "refuses to proceed when a different release branch already exists" {
    git checkout -qb release/9.9.9 develop
    run git-release-beta
    [ "$status" -eq 1 ]
    [[ "$output" == *"Other release exists"* ]]
    [[ "$output" == *"9.9.9"* ]]
}

@test "fails cleanly when the version cannot be computed" {
    rm -f "$TEST_BIN/gv"
    cat >"$TEST_BIN/gv" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_BIN/gv"
    run git-release-beta
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot compute release version"* ]]
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-release-beta
    [ "$status" -ne 0 ]
}
