#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    export REPO_DIR="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO_DIR"
    cd "$REPO_DIR"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo '{"name": "root", "version": "1.0.0"}' >package.json
    git add -A
    git commit -q -m "init"
    git tag v1.0.0
    git commit -q --allow-empty -m "feat: add a thing"
    git commit -q --allow-empty -m "fix: fix a thing"
}

teardown() {
    teardown_scripts_path
}

@test "bump-changelog is on PATH and syntactically valid" {
    run bash -n "$(command -v bump-changelog)"
    [ "$status" -eq 0 ]
}

@test "bump-changelog writes an incremental entry for commits since the last tag" {
    run bump-changelog -f 2.0.0
    [ "$status" -eq 0 ]
    [ -f CHANGELOG.md ]
    grep -q "## 2.0.0" CHANGELOG.md
    grep -q "add a thing" CHANGELOG.md
    grep -q "fix a thing" CHANGELOG.md
}

@test "bump-changelog -d dry-run does not write CHANGELOG.md" {
    run bump-changelog -f 2.0.0 -d
    [ "$status" -eq 0 ]
    [ ! -f CHANGELOG.md ]
}
