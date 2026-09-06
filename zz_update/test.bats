#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_update is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_update)"
    [ "$status" -eq 0 ]
}

@test "zz_update re-links the zz_* bundle from a local checkout without touching the network" {
    run zz_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"already available"* || "$output" == *"bundle"* ]]
}

@test "zz_update re-installs every core zz_* script (force, bypassing the already-available skip)" {
    bindir=$(mktemp -d)
    zz_update_bin=$(command -v zz_update)
    # zz_update execs `zz_use`, so zz_use itself (TEST_BIN) must stay on
    # PATH for that exec to resolve, even while we otherwise strip PATH
    # down to isolate the test.
    run env INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_update_bin"
    [ "$status" -eq 0 ]
    for tool in zz_use zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist zz_call zz_update; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

@test "zz_update makes no network request when run from a local checkout" {
    # Force curl to fail loudly if it is ever invoked, by shadowing it on
    # PATH ahead of the real one; a local-checkout install must never call
    # it, since zz_use resolves straight from ROOT_DIR in that case.
    fakebin=$(mktemp -d)
    cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
echo "UNEXPECTED NETWORK CALL: curl $*" >&2
exit 1
EOF
    chmod +x "$fakebin/curl"
    bindir=$(mktemp -d)
    run env INSTALL_BIN_DIR="$bindir" PATH="$fakebin:$PATH" zz_update
    [ "$status" -eq 0 ]
    [[ "$output" != *"UNEXPECTED NETWORK CALL"* ]]
    rm -rf "$fakebin" "$bindir"
}
