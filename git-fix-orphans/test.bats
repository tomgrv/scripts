#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    # gh stub: PR heads come from $PR_HEADS (one per line); jq filter ignored.
    stub_script gh <<'STUB'
#!/bin/sh
[ -n "$GH_FAIL" ] && exit 1
printf '%s\n' $PR_HEADS
STUB
    ORIGIN=$(mktemp -d)
    git init -q -b main --bare "$ORIGIN"
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q -b main
    git config user.email a@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    git remote add origin "$ORIGIN"
    echo one > f && git add f && git commit -qm "first"
    git config gitflow.branch.master main
    git config gitflow.branch.develop develop
    git config gitflow.prefix.feature feature/
    for b in develop feature/ok wip-nopr has-pr; do git branch "$b"; done
    git push -q origin --all
    git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
}

teardown() {
    cd /
    rm -rf "$REPO" "$ORIGIN"
    teardown_scripts_path
}

remote_branches() { git -C "$ORIGIN" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }

@test "git-fix-orphans is installed on PATH and syntactically valid" {
    command -v git-fix-orphans
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "git-fix-orphans -h prints usage and exits non-zero" {
    run git-fix-orphans -h </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "git-fix-orphans dry run lists but does not rename" {
    PR_HEADS="has-pr" run git-fix-orphans
    [ "$status" -eq 0 ]
    [[ "$output" == *"wip-nopr -> orphan/wip-nopr"* ]]
    [[ "$(remote_branches)" == *"wip-nopr"* ]]
    [[ "$(remote_branches)" != *"orphan/"* ]]
}

@test "git-fix-orphans -p renames only non compliant branches without a PR" {
    PR_HEADS="has-pr" run git-fix-orphans -p
    [ "$status" -eq 0 ]
    run remote_branches
    [[ "$output" == *"orphan/wip-nopr"* ]]
    [[ "$output" != *" wip-nopr "* ]]
    [[ "$output" == *"has-pr"* ]]
    [[ "$output" == *"feature/ok"* ]]
    [[ "$output" == *"develop"* ]]
    [[ "$output" == *"main"* ]]
}

@test "git-fix-orphans is idempotent" {
    PR_HEADS="has-pr" git-fix-orphans -p
    PR_HEADS="has-pr" run git-fix-orphans -p
    [ "$status" -eq 0 ]
    [[ "$output" != *"orphan/orphan/"* ]]
    [[ "$(remote_branches)" != *"orphan/orphan/"* ]]
}

@test "git-fix-orphans does nothing without gitflow config" {
    git config --unset gitflow.branch.master
    git config --unset gitflow.branch.develop
    PR_HEADS="" run git-fix-orphans -p
    [ "$status" -eq 0 ]
    [[ "$(remote_branches)" == *"wip-nopr"* ]]
}

@test "git-fix-orphans renames nothing when gh fails" {
    GH_FAIL=1 run git-fix-orphans -p
    [ "$status" -eq 1 ]
    [[ "$(remote_branches)" == *"wip-nopr"* ]]
}

@test "git-fix-orphans honours a custom prefix" {
    PR_HEADS="has-pr" run git-fix-orphans -p -x stale/
    [ "$status" -eq 0 ]
    [[ "$(remote_branches)" == *"stale/wip-nopr"* ]]
}
