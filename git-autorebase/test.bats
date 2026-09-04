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

@test "git-autorebase is installed on PATH and syntactically valid" {
    command -v git-autorebase
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    git init -q
    run git-autorebase -h
    [[ "$output" == *"non-interactive rebasing"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "fails cleanly outside a git repository" {
    run git-autorebase abc
    [[ "$output" == *"not a git repository"* ]]
}

@test "rebases the current branch onto an explicit sha with no conflicts" {
    git init -q
    echo base >f && git add f && git commit -qm base
    git checkout -qb topic
    echo t1 >>f && git add f && git commit -qm "topic change"
    git checkout -q main
    echo m1 >other.txt && git add other.txt && git commit -qm "main change"
    git checkout -q topic
    sha=$(git rev-parse main)

    run git-autorebase "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rebase completed without conflicts"* ]]
    [ -f other.txt ]
    [ "$(git log --format=%s -1)" = "topic change" ]
    [ "$(git rev-parse HEAD~1)" = "$sha" ]
}

@test "resolves a real content conflict using the default 'theirs' strategy" {
    git init -q
    echo base >f && git add f && git commit -qm base
    git checkout -qb topic
    echo topicline >f && git add f && git commit -qm "topic change"
    git checkout -q main
    echo mainline >f && git add f && git commit -qm "main change"
    git checkout -q topic
    sha=$(git rev-parse main)

    run git-autorebase "$sha"
    [ "$status" -eq 0 ]
    [ "$(cat f)" = "topicline" ]
    run git status --short
    [ -z "$output" ]
}

@test "-b rebases the named branch (not necessarily the current one) onto the target" {
    git init -q
    echo base >f && git add f && git commit -qm base
    git checkout -qb topic
    echo t1 >>f && git add f && git commit -qm "topic change"
    git checkout -q main
    git checkout -qb other
    sha=$(git rev-parse main)

    run git-autorebase -b topic "$sha"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse --abbrev-ref HEAD)" = "topic" ]
    [ "$(git rev-parse topic~1)" = "$sha" ]
}

@test "-o rebases onto a named branch instead of the sha argument" {
    git init -q
    echo base >f && git add f && git commit -qm base
    git checkout -qb feature-base
    echo fb >>f && git add f && git commit -qm "feature base change"
    git checkout -q main
    git checkout -qb topic
    echo t1 >>f && git add f && git commit -qm "topic change"

    run git-autorebase -o feature-base "$(git rev-parse feature-base)"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD~1)" = "$(git rev-parse feature-base)" ]
}

@test "-p pushes the rebased branch to origin (requires an origin/HEAD, e.g. from a clone)" {
    bare=$(mktemp -d)/origin.git
    git init -q --bare "$bare"

    seed=$(mktemp -d)
    (
        cd "$seed"
        git init -q
        git remote add origin "$bare"
        echo base >f && git add f && git commit -qm base
        git push -q origin HEAD:main
    )

    clone=$(mktemp -d)/work
    git clone -q "$bare" "$clone"
    cd "$clone"
    git checkout -qb topic
    echo t1 >>f && git add f && git commit -qm "topic change"
    sha=$(git rev-parse origin/main)

    run git-autorebase -p "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushing changes..."* ]]

    run git ls-remote "$bare" refs/heads/topic
    [ -n "$output" ]
}

@test "without -p, does not push anything to origin" {
    bare=$(mktemp -d)/origin.git
    git init -q --bare "$bare"
    seed=$(mktemp -d)
    (
        cd "$seed"
        git init -q
        git remote add origin "$bare"
        echo base >f && git add f && git commit -qm base
        git push -q origin HEAD:main
    )
    clone=$(mktemp -d)/work
    git clone -q "$bare" "$clone"
    cd "$clone"
    git checkout -qb topic
    echo t1 >>f && git add f && git commit -qm "topic change"
    sha=$(git rev-parse origin/main)

    run git-autorebase "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Pushing changes..."* ]]
    run git ls-remote "$bare" refs/heads/topic
    [ -z "$output" ]
}
