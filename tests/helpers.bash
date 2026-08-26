#!/usr/bin/env bash
# Shared bats setup: links repo-root *.sh scripts onto PATH under their
# public command names (zz_wrap/zz_use are sourced, not linked).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_scripts_path() {
    local file
    TEST_BIN=$(mktemp -d)
    for file in "$REPO_ROOT"/*.sh; do
        [ -f "$file" ] || continue
        chmod +x "$file"
        ln -sf "$file" "$TEST_BIN/$(basename "$file" | sed 's/\.sh$//')"
    done
    export PATH="$TEST_BIN:$PATH"
}

teardown_scripts_path() {
    rm -rf "$TEST_BIN"
}
