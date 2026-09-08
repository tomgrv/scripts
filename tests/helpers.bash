#!/usr/bin/env bash
# Shared bats setup: symlinks every <folder>/run.sh onto PATH under its
# folder name, the same way an install would. Config/resource files that
# live alongside a script's run.sh (e.g. validate-json/config/) stay
# resolvable because dirname(readlink -f "$0")) still finds the real folder.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_scripts_path() {
    local dir
    TEST_BIN=$(mktemp -d)
    for dir in "$REPO_ROOT"/*/; do
        [ -f "${dir}run.sh" ] || continue
        chmod +x "${dir}run.sh"
        ln -sf "${dir}run.sh" "$TEST_BIN/$(basename "$dir")"
    done
    export PATH="$TEST_BIN:$PATH"
}

# Replace a real script already symlinked onto $TEST_BIN (by
# setup_scripts_path) with a stub. Plain `cat >"$TEST_BIN/<name>"` would
# instead follow that pre-existing symlink and overwrite the real run.sh
# it points to (corrupting the actual script on disk) -- this removes the
# symlink first so the write lands on a fresh regular file. Takes the stub
# content on stdin, same as `cat >"$TEST_BIN/<name>"` would.
stub_script() {
    rm -f "$TEST_BIN/$1"
    cat >"$TEST_BIN/$1"
    chmod +x "$TEST_BIN/$1"
}

teardown_scripts_path() {
    rm -rf "$TEST_BIN"
}
