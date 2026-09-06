#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    REPO=$(mktemp -d)
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
    git config commit.gpgsign false
    git commit -q --allow-empty -m init
    git checkout -qb develop
}

teardown() {
    cd /
    rm -rf "$REPO"
    teardown_scripts_path
}

@test "git-release-alpha is installed on PATH and syntactically valid" {
    command -v git-release-alpha
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "--help prints usage and exits non-zero" {
    run git-release-alpha -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Release squashed current branch to develop branch"* ]]
}

@test "fails when no message is provided" {
    git checkout -qb feature/foo
    run git-release-alpha
    [ "$status" -eq 1 ]
    [[ "$output" == *"must provide a message"* ]]
}

@test "fails when not on a feature/ branch" {
    run git-release-alpha -m "feat: msg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be on a feature/xxx branch"* ]]
}

@test "squash-merges the feature branch into develop, scoping the message with the feature name" {
    git checkout -qb feature/foo
    echo 1 >f1.txt
    git add f1.txt
    git commit -qm "feat: add f1"

    run git-release-alpha -m "feat: msg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"successfully finished and squashed to develop"* ]]

    [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/foo" ]
    subject=$(git log develop -1 --pretty=%s)
    [ "$subject" = "feat(foo): msg" ]
    git show develop:f1.txt
}

@test "marks the squash commit as breaking when a commit uses the ! convention" {
    git checkout -qb feature/foo
    echo 1 >f1.txt
    git add f1.txt
    git commit -qm "feat!: breaking change"

    run git-release-alpha -m "feat: msg"
    [ "$status" -eq 0 ]
    subject=$(git log develop -1 --pretty=%s)
    [ "$subject" = "feat(foo)!: msg" ]
}

@test "uses the most occurring commit type when -o is given and types differ" {
    git checkout -qb feature/foo
    echo 1 >f1.txt
    git add f1.txt
    git commit -qm "fix: one"
    echo 2 >f2.txt
    git add f2.txt
    git commit -qm "fix: two"
    echo 3 >f3.txt
    git add f3.txt
    git commit -qm "chore: three"

    run git-release-alpha -m "misc: msg" -o
    [ "$status" -eq 0 ]
    subject=$(git log develop -1 --pretty=%s)
    [ "$subject" = "fix(foo): msg" ]
}

@test "restores stashed working-tree changes after finishing" {
    git checkout -qb feature/foo
    echo 1 >f1.txt
    git add f1.txt
    git commit -qm "feat: add f1"
    echo dirty >untracked.txt

    run git-release-alpha -m "feat: msg"
    [ "$status" -eq 0 ]
    [ "$(cat untracked.txt)" = "dirty" ]
    [ -z "$(git stash list)" ]
}

@test "pushes develop to origin when -p is given" {
    bare=$(mktemp -d)/origin.git
    git init -q --bare "$bare"
    git remote add origin "$bare"
    git push -qu origin develop

    git checkout -qb feature/foo
    echo 1 >f1.txt
    git add f1.txt
    git commit -qm "feat: add f1"

    run git-release-alpha -m "feat: msg" -p
    [ "$status" -eq 0 ]
    [[ "$output" == *"pushed to remote repository successfully"* ]]

    remote_subject=$(git --git-dir="$bare" log develop -1 --pretty=%s)
    [ "$remote_subject" = "feat(foo): msg" ]
    rm -rf "$bare"
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-release-alpha -m "feat: msg"
    [ "$status" -ne 0 ]
}
