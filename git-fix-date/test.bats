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

@test "git-fix-date is installed on PATH and syntactically valid" {
    command -v git-fix-date
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    run git-fix-date -h
    [[ "$output" == *"Fix commit dates and times"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "fails cleanly outside a git repository" {
    cd "$(mktemp -d)"
    run git-fix-date -d
    [ "$status" -ne 0 ]
}

@test "refuses to run with uncommitted changes present" {
    echo a >f && git add f && git commit -qm init
    echo dirty >f
    run git-fix-date -d
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "rejects invalid time formats" {
    echo a >f && git add f && git commit -qm init
    run git-fix-date -d -s "not-a-time"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid start time format"* ]]

    run git-fix-date -d -e "not-a-time"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid end time format"* ]]

    run git-fix-date -d -b "not-a-time"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid before time format"* ]]

    run git-fix-date -d -a "not-a-time"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid after time format"* ]]
}

@test "-d dry-run reports the reschedule plan without rewriting history" {
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-08T09:00:00" GIT_COMMITTER_DATE="2024-01-08T09:00:00" \
        git commit -qm "mon commit"
    before=$(git rev-parse HEAD)

    run git-fix-date -d
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN MODE"* ]]
    [[ "$output" == *"2024-01-08 09:00:00 → 2024-01-08 06:00:00"* ]]
    [[ "$output" == *"Dry run complete. No changes were made."* ]]

    [ "$(git rev-parse HEAD)" = "$before" ]
    [ "$(git log -1 --format=%ai)" = "2024-01-08 09:00:00 +0000" ]
}

@test "reschedules a commit in the first half of the range to the 'before' time (with confirmation)" {
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-08T09:00:00" GIT_COMMITTER_DATE="2024-01-08T09:00:00" \
        git commit -qm "mon commit"

    run bash -c 'echo y | git-fix-date'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git date fixup completed successfully."* ]]
    [ "$(git log -1 --format=%ai)" = "2024-01-08 06:00:00 +0000" ]
}

@test "reschedules a commit in the second half of the range to the 'after' time" {
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-08T16:00:00" GIT_COMMITTER_DATE="2024-01-08T16:00:00" \
        git commit -qm "mon afternoon commit"

    run bash -c 'echo y | git-fix-date'
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%ai)" = "2024-01-08 20:00:00 +0000" ]
}

@test "leaves commits outside the configured days/time range untouched" {
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-06T10:00:00" GIT_COMMITTER_DATE="2024-01-06T10:00:00" \
        git commit -qm "sat commit"

    run bash -c 'echo y | git-fix-date'
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%ai)" = "2024-01-06 10:00:00 +0000" ]
}

@test "an sha argument limits rescheduling to commits made after it" {
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-08T09:00:00" GIT_COMMITTER_DATE="2024-01-08T09:00:00" \
        git commit -qm c1
    sha1=$(git rev-parse HEAD)
    echo b >>f && git add f
    GIT_AUTHOR_DATE="2024-01-09T09:00:00" GIT_COMMITTER_DATE="2024-01-09T09:00:00" \
        git commit -qm c2

    run bash -c "echo y | git-fix-date '$sha1'"
    [ "$status" -eq 0 ]
    # c1 (before/at sha) is untouched, c2 (after sha) is rescheduled
    [ "$(git log --format=%ai -1 HEAD~1)" = "2024-01-08 09:00:00 +0000" ]
    [ "$(git log --format=%ai -1 HEAD)" = "2024-01-09 06:00:00 +0000" ]
}

@test "declining the confirmation prompt cancels without rewriting history" {
    echo z >f0 && git add f0 && git commit -qm base
    base_sha=$(git rev-parse HEAD)
    echo a >f && git add f
    GIT_AUTHOR_DATE="2024-01-08T09:00:00" GIT_COMMITTER_DATE="2024-01-08T09:00:00" \
        git commit -qm "mon commit"
    before=$(git rev-parse HEAD)

    # Pass sha explicitly so the "n" answer goes to the confirmation
    # prompt, not to git-getcommit's interactive "which commit?" prompt.
    run bash -c "echo n | git-fix-date '$base_sha'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled by user."* ]]
    [ "$(git rev-parse HEAD)" = "$before" ]
    [ "$(git log -1 --format=%ai)" = "2024-01-08 09:00:00 +0000" ]
}
