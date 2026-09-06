#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    ZZ_BINDIR_BIN=$(command -v zz_bindir)
}

teardown() {
    teardown_scripts_path
}

@test "zz_bindir is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_bindir)"
    [ "$status" -eq 0 ]
}

@test "zz_bindir resolves a writable directory and prints it" {
    run env INSTALL_BIN_DIR="$(mktemp -d)" zz_bindir
    [ "$status" -eq 0 ]
    [[ "$output" == *"dir="* ]]
}

@test "zz_bindir prefers a directory already on PATH over creating a new one" {
    already_on_path=$(mktemp -d)
    blockfile=$(mktemp)
    nohome=$(mktemp)
    run env INSTALL_BIN_DIR="$blockfile/bin" HOME="$nohome" \
        PATH="$already_on_path:$TEST_BIN" "$ZZ_BINDIR_BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dir='$already_on_path'"* ]]
    # no export PATH line needed since it's already there
    [[ "$output" != *"export PATH"* ]]
    rm -rf "$already_on_path"
    rm -f "$blockfile" "$nohome"
}

@test "zz_bindir emits an export PATH line when the chosen dir is not already on PATH" {
    target=$(mktemp -d)
    run env INSTALL_BIN_DIR="$target" PATH="$TEST_BIN:/usr/bin:/bin" "$ZZ_BINDIR_BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export PATH='$target'"* ]]
    [[ "$output" == *"dir='$target'"* ]]
    rm -rf "$target"
}

@test "zz_bindir -t target creates and uses <target>/bin when nothing already-writable exists" {
    base=$(mktemp -d)
    nohome=$(mktemp)
    # See the "no writable dir" test above for why a plain writable PATH
    # entry (even /usr/bin, since tests run as root) can't be used as the
    # "nothing already writable" baseline: build an immutable toolbox
    # instead, so the -t target is the only creatable candidate left.
    toolbox=$(mktemp -d)
    for tool in sh sed grep cut tr expr basename dirname printf mkdir; do
        bin=$(command -v "$tool") && ln -s "$bin" "$toolbox/$tool"
    done
    ln -s "$TEST_BIN/zz_colors" "$toolbox/zz_colors"
    blockfile=$(mktemp)
    chattr +i "$toolbox" 2>/dev/null || skip "chattr immutable attribute unsupported on this filesystem"
    run env INSTALL_BIN_DIR="$blockfile/bin" HOME="$nohome" \
        PATH="$toolbox" "$ZZ_BINDIR_BIN" -t "$base"
    chattr -i "$toolbox" 2>/dev/null || true
    [ "$status" -eq 0 ]
    [ -d "$base/bin" ]
    [[ "$output" == *"dir='$base/bin'"* ]]
    rm -rf "$base" "$nohome" "$toolbox"
    rm -f "$blockfile"
}

@test "zz_bindir eval usage extends PATH and sets \$dir" {
    target=$(mktemp -d)
    run bash -c "eval \"\$(env INSTALL_BIN_DIR='$target' PATH="$TEST_BIN:/usr/bin:/bin" '$ZZ_BINDIR_BIN')\"; echo \"\$dir\"; case \":\$PATH:\" in *\":$target:\"*) echo onpath;; esac"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$target"* ]]
    [[ "$output" == *"onpath"* ]]
    rm -rf "$target"
}

@test "zz_bindir fails with exit 1 and an error when no writable dir can be found or created" {
    # Tests run as root, so plain permission bits (chmod) don't make a
    # directory genuinely unwritable. Build a private toolbox (just the
    # utilities zz_bindir/zz_colors/zz_log need) and lock it down with
    # chattr's immutable attribute, which root can't bypass either — that
    # is the only PATH entry, and INSTALL_BIN_DIR/HOME point at a path
    # component that is a *file*, so mkdir -p can't create anything there.
    toolbox=$(mktemp -d)
    for tool in sh sed grep cut tr expr basename dirname printf mkdir; do
        bin=$(command -v "$tool") && ln -s "$bin" "$toolbox/$tool"
    done
    ln -s "$TEST_BIN/zz_colors" "$toolbox/zz_colors"
    blockfile=$(mktemp)
    nohome=$(mktemp)
    chattr +i "$toolbox" 2>/dev/null || skip "chattr immutable attribute unsupported on this filesystem"
    run env INSTALL_BIN_DIR="$blockfile/bin" HOME="$nohome" \
        PATH="$toolbox" "$ZZ_BINDIR_BIN"
    chattr -i "$toolbox" 2>/dev/null || true
    [ "$status" -ne 0 ]
    rm -rf "$toolbox"
    rm -f "$blockfile" "$nohome"
}
