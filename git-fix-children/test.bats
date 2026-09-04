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
    WORK=$(mktemp -d)
    cd "$WORK"
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$HOME"
    export HOME="$ORIG_HOME"
}

@test "git-fix-children is installed on PATH and syntactically valid" {
    command -v git-fix-children
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    git init -q
    run git-fix-children -h
    [[ "$output" == *"Delete all descendant tags and branches"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "fails cleanly outside a git repository" {
    run git-fix-children abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a git repository"* ]]
}

@test "no descendant tags or branches: succeeds cleanly (exit 0)" {
    git init -q
    echo a >f && git add f && git commit -qm c1
    sha=$(git rev-parse HEAD)

    run git-fix-children "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No descendant tags found"* ]]
    [[ "$output" == *"No descendant branches found"* ]]
}

@test "deletes descendant tags and branches, but preserves current/main/master" {
    git init -q
    echo a >f && git add f && git commit -qm c1
    sha1=$(git rev-parse HEAD)
    echo b >>f && git add f && git commit -qm c2
    git tag v1
    git branch feature
    echo c >>f && git add f && git commit -qm c3
    git tag v2

    run git-fix-children "$sha1"
    [ "$status" -eq 0 ]

    run git tag
    [ -z "$output" ]

    run git branch --format='%(refname:short)'
    [ "$output" = "main" ]
}

@test "without -p, warns that remote deletions were not pushed" {
    git init -q
    echo a >f && git add f && git commit -qm c1
    sha1=$(git rev-parse HEAD)
    echo b >>f && git add f && git commit -qm c2
    git tag v1

    run git-fix-children "$sha1"
    [[ "$output" == *"Remote deletions not pushed"* ]]
}

@test "-p pushes tag deletions to the remote" {
    bare=$(mktemp -d)/o.git
    git init -q --bare "$bare"
    git init -q
    git remote add origin "$bare"
    echo a >f && git add f && git commit -qm c1
    sha1=$(git rev-parse HEAD)
    echo b >>f && git add f && git commit -qm c2
    git tag v1
    git push -q origin HEAD:main --tags

    run git-fix-children -p "$sha1"
    [ "$status" -eq 0 ]

    run git ls-remote --tags "$bare"
    [ -z "$output" ]
}
