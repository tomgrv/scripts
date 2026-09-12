#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    # git-degit shells out to curl|tar. To keep tests hermetic (no network),
    # install a fake curl on PATH ahead of the real one: it ignores its
    # arguments and always emits a tarball with a single top-level
    # directory, mimicking a GitHub/GitLab/Bitbucket archive download.
    FAKE_BIN=$(mktemp -d)
    cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
tmp=$(mktemp -d)
mkdir -p "$tmp/repo-master"
echo "hello" >"$tmp/repo-master/README.md"
tar -C "$tmp" -czf - repo-master
rm -rf "$tmp"
EOF
    chmod +x "$FAKE_BIN/curl"
    export PATH="$FAKE_BIN:$PATH"

    WORK=$(mktemp -d)
    cd "$WORK"
}

teardown() {
    teardown_scripts_path
    cd /
    rm -rf "$WORK" "$FAKE_BIN"
}

@test "git-degit is installed on PATH and syntactically valid" {
    command -v git-degit
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "no arguments: prints usage and exits non-zero" {
    run git-degit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run git-degit -h
    [[ "$output" == *"Clone and degit a repository"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "unsupported host is rejected without attempting a download" {
    run git-degit https://example.com/foo/bar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported host"* ]]
    [ -z "$(ls -A .)" ]
}

@test "degits a github repo URL into the current directory by default" {
    run git-degit https://github.com/foo/bar
    [ "$status" -eq 0 ]
    [ -f README.md ]
    [ "$(cat README.md)" = "hello" ]
    # tarball's own top-level directory was stripped
    [ ! -d repo-master ]
}

@test "degits into the given target directory, creating it if needed" {
    run git-degit https://github.com/foo/bar mydir
    [ "$status" -eq 0 ]
    [ -f mydir/README.md ]
}

@test "recognizes gitlab.com and bitbucket.org hosts" {
    run git-degit https://gitlab.com/foo/bar gl-dir
    [ "$status" -eq 0 ]
    [ -f gl-dir/README.md ]

    run git-degit https://bitbucket.org/foo/bar bb-dir
    [ "$status" -eq 0 ]
    [ -f bb-dir/README.md ]
}

@test "strips a trailing .git suffix from the repository name" {
    run git-degit https://github.com/foo/bar.git gitsuffix-dir
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repository: foo/bar"* ]]
    [[ "$output" != *"bar.git"* ]]
}
