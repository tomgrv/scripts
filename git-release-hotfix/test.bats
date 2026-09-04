#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    # Stub git-flow's `hotfix start` (the real tool isn't installed) so the
    # script's own state/guard logic can be exercised hermetically.
    cat >"$TEST_BIN/git-flow" <<'EOF'
#!/bin/sh
sub=$1; shift
action=$1; shift
case "$sub-$action" in
    hotfix-start)
        name=$1
        git checkout -qb "hotfix/$name" main
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
    git branch -M main
    git tag v1.0.0
    git checkout -qb develop

    BARE=$(mktemp -d)/origin.git
    git init -q --bare "$BARE"
    git remote add origin "$BARE"
    git push -qu origin develop main --tags >/dev/null 2>&1
}

teardown() {
    cd /
    rm -rf "$REPO" "$(dirname "$BARE")"
    teardown_scripts_path
}

@test "git-release-hotfix is installed on PATH and syntactically valid" {
    command -v git-release-hotfix
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "--help prints usage and exits non-zero" {
    run git-release-hotfix -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Create HotFix branch"* ]]
}

@test "fails when main has no version tag" {
    git checkout -q main
    git tag -d v1.0.0
    git checkout -q develop
    run git-release-hotfix
    [ "$status" -eq 1 ]
    [[ "$output" == *"No tag found on main branch"* ]]
}

@test "creates a hotfix branch without rebasing when commits are not all fix:" {
    echo a >a.txt
    git add a.txt
    git commit -qm "feat: not a fix"

    run git-release-hotfix
    [ "$status" -eq 0 ]
    [[ "$output" == *"not of type 'fix:', creating hotfix branch only"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "hotfix/v1.0.X" ]
    # develop is untouched -- the non-fix commit is still there
    git log develop --oneline | grep -q "not a fix"
}

@test "creates a hotfix branch and rebases fix: commits from develop onto it" {
    echo a >a.txt
    git add a.txt
    git commit -qm "fix: bug a"
    echo b >b.txt
    git add b.txt
    git commit -qm "fix: bug b"

    run bash -c 'echo "" | git-release-hotfix'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rebasing current history"* ]]
    [[ "$output" == *"Successfully moved commits"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "hotfix/v1.0.X" ]
    git log hotfix/v1.0.X --oneline | grep -q "bug a"
    git log hotfix/v1.0.X --oneline | grep -q "bug b"
    # develop was reset back to the tagged commit
    [ "$(git rev-parse develop)" = "$(git rev-parse v1.0.0)" ]
}

@test "is idempotent: resumes an already-created hotfix branch instead of failing" {
    echo a >a.txt
    git add a.txt
    git commit -qm "feat: not a fix"
    git-release-hotfix >/dev/null 2>&1
    git checkout -q develop

    run git-release-hotfix
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists, resuming"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "hotfix/v1.0.X" ]
}

@test "refuses to rebase when develop has already been pushed to remote" {
    echo a >a.txt
    git add a.txt
    git commit -qm "fix: bug a"
    git push -q origin develop

    run git-release-hotfix
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot rebase safely"* ]]
}

@test "-r forces a rebase even when commits are not all fix:" {
    echo a >a.txt
    git add a.txt
    git commit -qm "feat: not a fix"

    run bash -c 'echo "" | git-release-hotfix -r'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rebase forced via command line option"* ]]
    git log hotfix/v1.0.X --oneline | grep -q "not a fix"
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-release-hotfix
    [ "$status" -ne 0 ]
}
