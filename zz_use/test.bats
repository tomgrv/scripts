#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_use is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_use)"
    [ "$status" -eq 0 ]
}

@test "zz_use skips a tool already on PATH" {
    run env ZZ_DEBUG=1 zz_use sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"already available"* ]]
}

@test "zz_use requires at least one tool argument" {
    run zz_use
    [ "$status" -ne 0 ]
}

@test "zz_use's usage error prints even when zz_log isn't resolvable yet" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: zz_use"* ]]
}

@test "zz_use rejects an unknown option instead of treating it as a tool name" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" zz_log --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "zz_use installs a functional script individually, not the whole bundle" {
    bindir=$(mktemp -d)
    # PATH is restricted to hide load-json/validate-json (already linked
    # onto TEST_BIN by setup_scripts_path, which would make load-json
    # trivially "already available" instead of exercising real install
    # logic) — but zz_use itself is resolved to an absolute path first, so
    # restricting PATH for the child doesn't also hide zz_use.
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" load-json
    [ "$status" -eq 0 ]
    [ -x "$bindir/load-json" ]
    [ ! -e "$bindir/validate-json" ]
    rm -rf "$bindir"
}

@test "zz_use installs a single zz_* tool individually, not the whole set" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz_log
    [ "$status" -eq 0 ]
    [ -x "$bindir/zz_log" ]
    [ ! -e "$bindir/zz_args" ]
    rm -rf "$bindir"
}

@test "zz_use expands a zz_* glob to the full bundle" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "zz_*"
    [ "$status" -eq 0 ]
    for tool in zz_use zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist zz_call zz_update; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

@test "zz_use warns rather than fails for a glob that matches nothing" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "totally-bogus-glob-*"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No scripts match"* ]]
    rm -rf "$bindir"
}

@test "zz_use errors out for a tool that cannot be resolved by any install path" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" totally-bogus-tool-xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unable to provide required dependency"* ]]
    rm -rf "$bindir"
}

@test "zz_use --force re-installs the zz_* bundle even when already on PATH" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    # First install normally so files exist with an old mtime, then force
    # a re-install and check it does not merely say "already available".
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz_log
    [ "$status" -eq 0 ]
    run env INSTALL_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" "$zz_use_bin" --force zz_log
    [ "$status" -eq 0 ]
    [[ "$output" != *"already available"* ]]
    rm -rf "$bindir"
}

@test "zz_use recognizes --force after a tool name, not just as the first arg" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz_log
    [ "$status" -eq 0 ]
    run env INSTALL_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" "$zz_use_bin" zz_log --force
    [ "$status" -eq 0 ]
    [[ "$output" != *"already available"* ]]
    [[ "$output" != *"Unknown option"* ]]
    rm -rf "$bindir"
}

@test "zz_use resolves a functional script's config/ folder alongside it" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" validate-json
    [ "$status" -eq 0 ]
    [ -x "$bindir/validate-json" ]
    rm -rf "$bindir"
}

@test "zz_use -x installs the target and execs it, passing arguments through" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x sh -c "echo hello-from-exec"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello-from-exec"* ]]
}

@test "zz_use -x propagates the exec'd command's exit status" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x sh -c "exit 7"
    [ "$status" -eq 7 ]
}

@test "zz_use -x resolves leading dependencies before installing/exec'ing the target" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" load-json -x zz_log w "warned"
    [ "$status" -eq 0 ]
    [ -x "$bindir/load-json" ]
    [[ "$output" == *"warned"* ]]
    rm -rf "$bindir"
}

@test "zz_use -x strips an [org/repo/] prefix from the exec target's command name" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x tomgrv/scripts/zz_log w "pinned"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinned"* ]]
}

@test "zz_use resolves a ./ local-path origin relative to cwd, no download" {
    local_repo=$(mktemp -d)
    mkdir -p "$local_repo/some-tool"
    cat >"$local_repo/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo from-local-repo
EOF
    chmod +x "$local_repo/some-tool/run.sh"

    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run bash -c "cd '$(dirname "$local_repo")' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' '$zz_use_bin' './$(basename "$local_repo")/some-tool'"
    [ "$status" -eq 0 ]
    [ -x "$bindir/some-tool" ]
    [[ "$("$bindir/some-tool")" == "from-local-repo" ]]
    rm -rf "$local_repo" "$bindir"
}

@test "zz_use errors on a ./ local-path origin that doesn't exist" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz_use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" ./totally-bogus-local-dir/some-tool
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    rm -rf "$bindir"
}

@test "zz_use -x without a tool name errors" {
    zz_use_bin=$(command -v zz_use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a tool name"* ]]
}
