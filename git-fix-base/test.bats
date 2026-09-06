#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ORIG_HOME="$HOME"
    export HOME="$(mktemp -d)"
    git config --global user.name t
    git config --global user.email t@t.com
    git config --global commit.gpgsign false
    git config --global init.defaultBranch main
    BARE=$(mktemp -d)/origin.git
    git init -q --bare "$BARE"
    WORK=$(mktemp -d)
    cd "$WORK"
    git init -q
    git remote add origin "$BARE"
    echo base >base.txt && git add base.txt && git commit -qm base
    git push -q origin HEAD:main
    git checkout -qb target
    git push -q origin HEAD:target
    git checkout -qb source
    git push -q origin HEAD:source
    echo a >a.txt && git add a.txt && git commit -qm "commit-a"
    echo b >b.txt && git add b.txt && git commit -qm "commit-b"
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$HOME" "$(dirname "$BARE")"
}

@test "git-fix-base is installed on PATH and syntactically valid" {
    command -v git-fix-base
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    run git-fix-base -h
    [[ "$output" == *"Fix git base"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "missing target is required and exits non-zero" {
    run git-fix-base
    [ "$status" -eq 1 ]
    [[ "$output" == *"Target branch is required"* ]]
}

@test "rejects a target branch that does not exist" {
    run git-fix-base nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "rejects a source branch that does not exist" {
    run git-fix-base target nope-source
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "rejects identical source and target branches" {
    run git-fix-base source source
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be the same"* ]]
}

@test "-n dry-run lists the commits without changing any branch" {
    target_before=$(git rev-parse target)
    source_before=$(git rev-parse source)

    run git-fix-base -n target source
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commits that would be moved"* ]]
    [[ "$output" == *"commit-a"* ]]
    [[ "$output" == *"commit-b"* ]]

    [ "$(git rev-parse target)" = "$target_before" ]
    [ "$(git rev-parse source)" = "$source_before" ]
}

@test "with no unpushed commits, reports nothing to move and exits 0" {
    git checkout -q source
    git reset -q --hard origin/source
    run git-fix-base target source
    [ "$status" -eq 0 ]
    [[ "$output" == *"No commits to move"* ]]
}

@test "moves unpushed commits from source onto target and resets source to the merge base (with confirmation)" {
    run bash -c 'echo y | git-fix-base target source'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully moved commits"* ]]

    # target now carries both commits
    [ "$(git log --oneline target | wc -l)" -eq 3 ]
    [[ "$(git log --format=%s target)" == *"commit-a"* ]]
    [[ "$(git log --format=%s target)" == *"commit-b"* ]]

    # source was reset back to the merge base
    [ "$(git rev-parse source)" = "$(git rev-parse target~2)" ]

    # no leftover temp branch
    run git branch --list 'temp-fix-base-*'
    [ -z "$output" ]
}

@test "declining the confirmation prompt cancels without changing any branch" {
    target_before=$(git rev-parse target)
    source_before=$(git rev-parse source)

    run bash -c 'echo n | git-fix-base target source'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled"* ]]

    [ "$(git rev-parse target)" = "$target_before" ]
    [ "$(git rev-parse source)" = "$source_before" ]
}

@test "fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-base target
    [ "$status" -ne 0 ]
}
