#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ORIG_HOME="$HOME"
    export HOME="$(mktemp -d)"
    git config --global user.name "Test User"
    git config --global user.email "test@example.com"
    git config --global commit.gpgsign false
    git config --global init.defaultBranch main
    WORK=$(mktemp -d)
}

teardown() {
    teardown_scripts_path
    rm -rf "$WORK" "$HOME"
    export HOME="$ORIG_HOME"
}

@test "git-align is installed on PATH and syntactically valid" {
    command -v git-align
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails cleanly outside a git repository" {
    cd "$WORK"
    run git-align
    [[ "$output" == *"not a git repository"* ]]
}

@test "with no remote configured, logs a failure and leaves the branch/history intact" {
    cd "$WORK"
    git init -q
    git config commit.gpgsign false
    echo a >f && git add f && git commit -qm init
    before=$(git rev-parse HEAD)
    run git-align
    [[ "$output" == *"Failed to checkout branch"* ]]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "aligns the current branch to a newer remote commit and restores stashed changes" {
    bare=$(mktemp -d)/origin.git
    git init -q --bare "$bare"

    git clone -q "$bare" "$WORK/work"
    (
        cd "$WORK/work"
        git config commit.gpgsign false
        echo a >f && git add f && git commit -qm init
        git push -q origin HEAD:main
        git branch --set-upstream-to=origin/main main
    )

    # Someone else pushes a new commit to the "remote".
    other=$(mktemp -d)
    git clone -q "$bare" "$other"
    (
        cd "$other"
        git config user.name t && git config user.email t@t.com
        git config commit.gpgsign false
        echo b >f2 && git add f2 && git commit -qm "remote change"
        git push -q origin HEAD:main
    )

    cd "$WORK/work"
    echo "local edit" >f
    run git-align
    [ "$status" -eq 0 ]
    [[ "$output" == *"Current branch: main"* ]]

    # The remote commit landed locally.
    [ -f f2 ]
    [ "$(git log --oneline | wc -l)" -eq 2 ]
    # Branch name preserved.
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
    # Stashed local edit was restored.
    [ "$(cat f)" = "local edit" ]
    # No leftover temp/stash branch.
    ! git show-ref --verify --quiet refs/heads/main-to-delete
}

@test "aligns cleanly with no uncommitted changes (nothing to stash/pop)" {
    bare=$(mktemp -d)/origin.git
    git init -q --bare "$bare"
    git clone -q "$bare" "$WORK/work"
    (
        cd "$WORK/work"
        git config commit.gpgsign false
        echo a >f && git add f && git commit -qm init
        git push -q origin HEAD:main
        git branch --set-upstream-to=origin/main main
    )
    cd "$WORK/work"
    run git-align
    [ "$status" -eq 0 ]
    [[ "$output" == *"Current branch: main"* ]]
}
