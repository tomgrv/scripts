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

teardown_scripts_path() {
    rm -rf "$TEST_BIN"
}
