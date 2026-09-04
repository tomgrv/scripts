#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    # Stub the external tools git-release-prod shells out to (GitVersion
    # `gv`, git-flow, and the sibling bump-tag/bump-changelog helpers), none
    # of which are installed here, so its own resolution/guard logic runs
    # for real against a real git repo.
    cat >"$TEST_BIN/gv" <<'EOF'
#!/bin/sh
echo "${GBV_STUB:-1.2.3}"
EOF
    chmod +x "$TEST_BIN/gv"

    cat >"$TEST_BIN/bump-changelog" <<'EOF'
#!/bin/sh
echo "changelog bumped" >>CHANGELOG.md
git add CHANGELOG.md
EOF
    chmod +x "$TEST_BIN/bump-changelog"

    cat >"$TEST_BIN/bump-tag" <<'EOF'
#!/bin/sh
echo "bump-tag $1" >>"$BATS_TEST_TMPDIR/bump-tag.log"
EOF
    chmod +x "$TEST_BIN/bump-tag"

    cat >"$TEST_BIN/git-flow" <<'EOF'
#!/bin/sh
sub=$1; shift
action=$1; shift
name=$1; shift
tagname="$name"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tagname) tagname=$2; shift 2 ;;
        *) shift ;;
    esac
done
case "$sub-$action" in
    release-finish|hotfix-finish)
        git checkout -q main
        git merge -q --no-ff "$sub/$name" -m "merge $sub/$name" || exit 1
        git tag "v$tagname"
        git checkout -q develop
        git merge -q --no-ff "$sub/$name" -m "merge $sub/$name into develop" || exit 1
        git branch -D "$sub/$name"
        git push -q origin main develop "v$tagname" 2>/dev/null || true
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
    git checkout -qb develop

    BARE=$(mktemp -d)/origin.git
    git init -q --bare "$BARE"
    git remote add origin "$BARE"
    git push -qu origin develop main >/dev/null 2>&1
}

teardown() {
    cd /
    rm -rf "$REPO" "$(dirname "$BARE")"
    teardown_scripts_path
}

@test "git-release-prod is installed on PATH and syntactically valid" {
    command -v git-release-prod
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "--help prints usage and exits non-zero" {
    run git-release-prod -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Release production branch"* ]]
}

@test "fails when there is no release or hotfix branch to finish" {
    run git-release-prod
    [ "$status" -eq 1 ]
    [[ "$output" == *"No flow branch found"* ]]
}

@test "finishes the current release branch: bumps changelog, merges, tags and cleans up" {
    git checkout -qb release/1.2.3 develop
    git push -qu origin release/1.2.3 >/dev/null 2>&1
    echo x >x.txt
    git add x.txt
    git commit -qm "feat: x"
    git push -q origin release/1.2.3

    run git-release-prod
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release finished: {B 1.2.3}"* || "$output" == *"Release finished"* ]]
    git rev-parse --verify refs/tags/v1.2.3
    ! git show-ref --verify --quiet refs/heads/release/1.2.3
    [ ! -f .git/RELEASE ]
    [ "$(cat "$BATS_TEST_TMPDIR/bump-tag.log")" = "bump-tag 1.2.3" ]
}

@test "fails when the working directory is not clean" {
    git checkout -qb release/1.2.3 develop
    git push -qu origin release/1.2.3 >/dev/null 2>&1
    echo dirty >dirty.txt

    run git-release-prod
    [ "$status" -eq 1 ]
    [[ "$output" == *"not clean"* ]]
}

@test "refuses to pick a branch when multiple release branches exist" {
    git checkout -qb release/1.0.0 develop
    git checkout -qb release/2.0.0 develop
    git checkout -q develop

    run git-release-prod
    [ "$status" -eq 1 ]
    [[ "$output" == *"Multiple release branches found"* ]]
}

@test "prefers a hotfix branch over an ambiguous discovery when checked out" {
    git checkout -qb hotfix/1.2.4 develop
    git push -qu origin hotfix/1.2.4 >/dev/null 2>&1
    echo fix >fix.txt
    git add fix.txt
    git commit -qm "fix: it"
    git push -q origin hotfix/1.2.4

    run git-release-prod
    [ "$status" -eq 0 ]
    [[ "$output" == *"On hotfix branch"* ]]
    git rev-parse --verify refs/tags/v1.2.3
}

@test "is idempotent: resuming after the finish tag already exists only runs cleanup" {
    git checkout -qb release/1.2.3 develop
    git push -qu origin release/1.2.3 >/dev/null 2>&1
    echo x >x.txt
    git add x.txt
    git commit -qm "feat: x"
    git push -q origin release/1.2.3

    # Simulate a run interrupted right after `git flow ... finish` created
    # the tag but before it deleted the branch / returned success (e.g. the
    # final push failed): the tag exists but the release branch is still
    # there and .git/RELEASE was never cleared.
    cat >"$TEST_BIN/git-flow" <<'EOF'
#!/bin/sh
git tag "v1.2.3"
exit 1
EOF
    chmod +x "$TEST_BIN/git-flow"
    run git-release-prod
    [ "$status" -eq 1 ]
    git rev-parse --verify refs/tags/v1.2.3
    git show-ref --verify --quiet refs/heads/release/1.2.3

    # Re-running now must not try to redo the merge/tag/push, only resume
    # the trailing bump-tag/cleanup step.
    run git-release-prod
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists, release already finished -- resuming cleanup only"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/bump-tag.log")" = "bump-tag 1.2.3" ]
    [ ! -f .git/RELEASE ]
}

@test "fails cleanly outside a git repository" {
    cd /
    run git-release-prod
    [ "$status" -ne 0 ]
}
