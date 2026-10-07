#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-update is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-update)"
    [ "$status" -eq 0 ]
}

@test "zz-update re-links the core zz-* scripts from a local checkout without touching the network" {
    run zz-update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed"* ]]
}

@test "zz-update re-installs every core zz-* script (force, bypassing the already-available skip)" {
    bindir=$(mktemp -d)
    zz_update_bin=$(command -v zz-update)
    # zz-update execs `zz-use`, so zz-use itself (TEST_BIN) must stay on
    # PATH for that exec to resolve, even while we otherwise strip PATH
    # down to isolate the test.
    run env INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_update_bin"
    [ "$status" -eq 0 ]
    for tool in zz-use zz-colors zz-log zz-args zz-prompt zz-ask zz-menu zz-input zz-bindir zz-dispatch zz-npx zz-persist zz-call zz-update; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

@test "zz-update makes no network request when run from a local checkout" {
    # Force curl to fail loudly if it is ever invoked, by shadowing it on
    # PATH ahead of the real one; a local-checkout install must never call
    # it, since zz-use resolves straight from ROOT_DIR in that case.
    fakebin=$(mktemp -d)
    cat >"$fakebin/curl" <<'EOF'
#!/bin/sh
echo "UNEXPECTED NETWORK CALL: curl $*" >&2
exit 1
EOF
    chmod +x "$fakebin/curl"
    bindir=$(mktemp -d)
    run env INSTALL_BIN_DIR="$bindir" PATH="$fakebin:$PATH" zz-update
    [ "$status" -eq 0 ]
    [[ "$output" != *"UNEXPECTED NETWORK CALL"* ]]
    rm -rf "$fakebin" "$bindir"
}
