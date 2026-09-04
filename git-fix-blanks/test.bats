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
    git init -q
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$HOME"
    export HOME="$ORIG_HOME"
}

@test "git-fix-blanks is installed on PATH and syntactically valid" {
    command -v git-fix-blanks
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    run git-fix-blanks -h
    [[ "$output" == *"Discard changes made only of whitespace"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "no modified tracked files: reports nothing to do" {
    printf 'line1\nline2\n' >f.txt
    git add f.txt && git commit -qm init
    run git-fix-blanks
    [ "$status" -eq 0 ]
    [[ "$output" == *"No modified tracked files found."* ]]
}

@test "-d dry-run reports discardable whitespace-only changes without touching the working tree" {
    printf 'line1\nline2\n' >f.txt
    git add f.txt && git commit -qm init
    printf 'line1  \nline2\n' >f.txt

    run git-fix-blanks -d
    [ "$status" -eq 0 ]
    [[ "$output" == *"Discarding ignorable-only changes in f.txt"* ]]
    [[ "$output" == *"Dry run complete. Discardable files: 1, kept: 0, skipped: 0"* ]]

    # working tree change is still present
    run git diff --stat
    [ -n "$output" ]
}

@test "discards a whitespace-only modification" {
    printf 'line1\nline2\n' >f.txt
    git add f.txt && git commit -qm init
    printf 'line1  \nline2\n' >f.txt

    run git-fix-blanks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Done. Discarded: 1, kept: 0, skipped: 0"* ]]

    run git diff --stat
    [ -z "$output" ]
}

@test "keeps a real content change" {
    printf 'line1\nline2\n' >f.txt
    git add f.txt && git commit -qm init
    printf 'line1\nline2 changed\n' >f.txt

    run git-fix-blanks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Done. Discarded: 0, kept: 1, skipped: 0"* ]]

    run git diff --stat
    [ -n "$output" ]
}

@test "discards a comment-only change in a .sh file" {
    printf '# comment\nfoo\n' >s.sh
    git add s.sh && git commit -qm init
    printf '# comment changed\nfoo\n' >s.sh

    run git-fix-blanks
    [[ "$output" == *"Discarded: 1, kept: 0, skipped: 0"* ]]
    [ "$(cat s.sh)" = "$(printf '# comment\nfoo\n')" ]
}

@test "deleted tracked files are not touched (diff-filter=M excludes deletions)" {
    printf 'a\n' >d.txt
    git add d.txt && git commit -qm add
    rm d.txt

    run git-fix-blanks
    [ "$status" -eq 0 ]
    [[ "$output" == *"No modified tracked files found."* ]]
    run git status --short
    [[ "$output" == *"D d.txt"* ]]
}

@test "outside a git repository, exits cleanly reporting no modified files" {
    cd "$(mktemp -d)"
    run git-fix-blanks
    [ "$status" -eq 0 ]
    [[ "$output" == *"No modified tracked files found."* ]]
}
