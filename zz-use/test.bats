#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-use is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-use)"
    [ "$status" -eq 0 ]
}

@test "zz-use skips a tool already on PATH" {
    run env ZZ_DEBUG=1 zz-use sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"already available"* ]]
}

@test "zz-use requires at least one tool argument" {
    run zz-use
    [ "$status" -ne 0 ]
}

@test "zz-use's usage error prints even when zz-log isn't resolvable yet" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: zz-use"* ]]
}

@test "zz-use rejects an unknown option instead of treating it as a tool name" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" zz-log --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "zz-use installs a functional script individually, not the whole bundle" {
    bindir=$(mktemp -d)
    # PATH is restricted to hide json-load/json-validate (already linked
    # onto TEST_BIN by setup_scripts_path, which would make json-load
    # trivially "already available" instead of exercising real install
    # logic) — but zz-use itself is resolved to an absolute path first, so
    # restricting PATH for the child doesn't also hide zz-use.
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" json-load
    [ "$status" -eq 0 ]
    [ -x "$bindir/json-load" ]
    [ ! -e "$bindir/json-validate" ]
    rm -rf "$bindir"
}

@test "zz-use installs a single zz-* tool individually, not the whole set" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz-log
    [ "$status" -eq 0 ]
    [ -x "$bindir/zz-log" ]
    [ ! -e "$bindir/zz-args" ]
    rm -rf "$bindir"
}

@test "zz-use expands a zz-* glob to the full bundle" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "zz-*"
    [ "$status" -eq 0 ]
    for tool in zz-use zz-colors zz-log zz-args zz-prompt zz-ask zz-menu zz-input zz-bindir zz-dispatch zz-npx zz-persist zz-call zz-update; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

@test "zz-use warns rather than fails for a glob that matches nothing" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "totally-bogus-glob-*"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No scripts match"* ]]
    rm -rf "$bindir"
}

@test "zz-use errors out for a tool that cannot be resolved by any install path" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" totally-bogus-tool-xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unable to provide required dependency"* ]]
    rm -rf "$bindir"
}

@test "zz-use --force re-installs the zz-* bundle even when already on PATH" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    # First install normally so files exist with an old mtime, then force
    # a re-install and check it does not merely say "already available".
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz-log
    [ "$status" -eq 0 ]
    run env INSTALL_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" "$zz_use_bin" --force zz-log
    [ "$status" -eq 0 ]
    [[ "$output" != *"already available"* ]]
    rm -rf "$bindir"
}

@test "zz-use recognizes --force after a tool name, not just as the first arg" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" zz-log
    [ "$status" -eq 0 ]
    run env INSTALL_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" "$zz_use_bin" zz-log --force
    [ "$status" -eq 0 ]
    [[ "$output" != *"already available"* ]]
    [[ "$output" != *"Unknown option"* ]]
    rm -rf "$bindir"
}

@test "zz-use resolves a functional script's config/ folder alongside it" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" json-validate
    [ "$status" -eq 0 ]
    [ -x "$bindir/json-validate" ]
    rm -rf "$bindir"
}

@test "zz-use -x installs the target and execs it, passing arguments through" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x sh -c "echo hello-from-exec"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello-from-exec"* ]]
}

@test "zz-use -x propagates the exec'd command's exit status" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x sh -c "exit 7"
    [ "$status" -eq 7 ]
}

@test "zz-use -x resolves leading dependencies before installing/exec'ing the target" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" json-load -x zz-log w "warned"
    [ "$status" -eq 0 ]
    [ -x "$bindir/json-load" ]
    [[ "$output" == *"warned"* ]]
    rm -rf "$bindir"
}

@test "zz-use -x strips an [org/repo/] prefix from the exec target's command name" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x tomgrv/scripts/zz-log w "pinned"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinned"* ]]
}

@test "zz-use resolves a ./ local-path origin relative to cwd, no download" {
    local_repo=$(mktemp -d)
    mkdir -p "$local_repo/some-tool"
    cat >"$local_repo/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo from-local-repo
EOF
    chmod +x "$local_repo/some-tool/run.sh"

    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run bash -c "cd '$(dirname "$local_repo")' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' '$zz_use_bin' './$(basename "$local_repo")/some-tool'"
    [ "$status" -eq 0 ]
    [ -x "$bindir/some-tool" ]
    [[ "$("$bindir/some-tool")" == "from-local-repo" ]]
    rm -rf "$local_repo" "$bindir"
}

@test "zz-use resolves a bare ./tool or ../tool origin, not as an npm package" {
    local_repo=$(mktemp -d)
    mkdir -p "$local_repo/some-tool" "$local_repo/sub"
    cat >"$local_repo/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo from-cwd
EOF
    chmod +x "$local_repo/some-tool/run.sh"

    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run bash -c "cd '$local_repo' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' '$zz_use_bin' ./some-tool"
    [ "$status" -eq 0 ]
    [[ "$output" != *"npm"* ]]
    [[ "$("$bindir/some-tool")" == "from-cwd" ]]

    rm -f "$bindir/some-tool"
    run bash -c "cd '$local_repo/sub' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' '$zz_use_bin' ../some-tool"
    [ "$status" -eq 0 ]
    [[ "$("$bindir/some-tool")" == "from-cwd" ]]
    rm -rf "$local_repo" "$bindir"
}

@test "zz-use errors on a ./ local-path origin that doesn't exist" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" ./totally-bogus-local-dir/some-tool
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    rm -rf "$bindir"
}

@test "zz-use resolves a \$ git-root origin relative to the repo top level" {
    git_repo=$(mktemp -d)
    (cd "$git_repo" && git init -q)
    mkdir -p "$git_repo/some-tool" "$git_repo/nested/dir"
    cat >"$git_repo/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo from-git-root
EOF
    chmod +x "$git_repo/some-tool/run.sh"

    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    # Run from a nested subdirectory to prove it's resolved off the repo
    # top level, not the caller's own cwd (a plain "./" origin wouldn't
    # find it from here).
    run bash -c "cd '$git_repo/nested/dir' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' '$zz_use_bin' '\$/some-tool'"
    [ "$status" -eq 0 ]
    [ -x "$bindir/some-tool" ]
    [[ "$("$bindir/some-tool")" == "from-git-root" ]]
    rm -rf "$git_repo" "$bindir"
}

@test "zz-use errors on a \$ git-root origin outside any git repository" {
    non_repo=$(mktemp -d)
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run bash -c "cd '$non_repo' && INSTALL_BIN_DIR='$bindir' PATH='/usr/bin:/bin' HOME='$non_repo' '$zz_use_bin' '\$/some-tool'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not inside a git repository"* ]]
    rm -rf "$non_repo" "$bindir"
}

# Shared by both npm-origin tests below: stubs the registry round-trip
# (curl serves fixed metadata for <registry_url_glob>, then the tarball
# bytes for whatever "tarball" URL that metadata pointed to — no real
# network) and asserts zz-use <use_arg> installs a working some-tool.
_npm_resolve_test() {
    registry_url_glob="$1" use_arg="$2"

    tarball=$(mktemp)
    tar_src=$(mktemp -d)
    mkdir -p "$tar_src/package/some-tool"
    cat >"$tar_src/package/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo from-npm-registry
EOF
    chmod +x "$tar_src/package/some-tool/run.sh"
    tar -C "$tar_src" -czf "$tarball" package

    stub_script curl <<EOF
#!/bin/sh
url=""
out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
    esac
done
[ -z "\$out" ] || exec >"\$out"
case "\$url" in
${registry_url_glob})
    printf '{"dist":{"tarball":"http://fake-registry.invalid/tarball.tgz"}}'
    ;;
*fake-registry.invalid/tarball.tgz*)
    cat "$tarball"
    ;;
*)
    exit 1
    ;;
esac
EOF

    zz_cache_dir=$(mktemp -d)
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env ZZ_CACHE_DIR="$zz_cache_dir" INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" "$use_arg"
    [ "$status" -eq 0 ]
    [ -x "$bindir/some-tool" ]
    [[ "$("$bindir/some-tool")" == "from-npm-registry" ]]
    rm -rf "$tarball" "$tar_src" "$zz_cache_dir" "$bindir"
}

@test "zz-use resolves an @ npm origin, splitting a pinned @ref from the scope's own leading @" {
    _npm_resolve_test "*'registry.npmjs.org/@myscope%2fpkg/1.2.3'*" "@myscope/pkg/some-tool@1.2.3"
}

@test "zz-use resolves an unscoped npm origin (no @, no /)" {
    # npm's other valid package-name shape: a bare "mypkg", no leading "@"
    # and no "/" of its own — the case a GitHub "org/repo" origin, which
    # always has a "/", can never collide with.
    _npm_resolve_test "*'registry.npmjs.org/mypkg/latest'*" "mypkg/some-tool"
}

@test "zz-use -x strips an npm scope's own @ from the exec target's command name, keeping a real @ref" {
    tarball=$(mktemp)
    tar_src=$(mktemp -d)
    mkdir -p "$tar_src/package/some-tool"
    cat >"$tar_src/package/some-tool/run.sh" <<'EOF'
#!/bin/sh
echo "exec'd-from-npm $*"
EOF
    chmod +x "$tar_src/package/some-tool/run.sh"
    tar -C "$tar_src" -czf "$tarball" package

    stub_script curl <<EOF
#!/bin/sh
url=""
out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
    esac
done
[ -z "\$out" ] || exec >"\$out"
case "\$url" in
*'registry.npmjs.org/@myscope%2fpkg/1.2.3'*)
    printf '{"dist":{"tarball":"http://fake-registry.invalid/tarball.tgz"}}'
    ;;
*fake-registry.invalid/tarball.tgz*)
    cat "$tarball"
    ;;
*)
    exit 1
    ;;
esac
EOF

    zz_cache_dir=$(mktemp -d)
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env ZZ_CACHE_DIR="$zz_cache_dir" INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" -x "@myscope/pkg/some-tool@1.2.3" arg1
    [ "$status" -eq 0 ]
    [[ "$output" == *"exec'd-from-npm arg1"* ]]
    rm -rf "$tarball" "$tar_src" "$zz_cache_dir" "$bindir"
}

@test "zz-use -x without a tool name errors" {
    zz_use_bin=$(command -v zz-use)
    run env PATH="/usr/bin:/bin" "$zz_use_bin" -x
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a tool name"* ]]
}

@test "zz-use persists a script's zz-* peers, not just the scratch boot-dir copies" {
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" git-hook-commitmsg
    [ "$status" -eq 0 ]
    for tool in git-hook-commitmsg git-hook-installplugins zz-args zz-colors zz-log zz-npx; do
        [ -x "$bindir/$tool" ]
    done
    rm -rf "$bindir"
}

# A local-origin fixture repo: a-tool peers on b-tool (only in the
# fixture) and zz-log (default origin); c-tool has no peers.
_local_fixture() {
    fx=$(mktemp -d)
    for t in a-tool b-tool c-tool; do
        mkdir -p "$fx/$t"
        printf '#!/bin/sh\necho fixture-%s\n' "$t" >"$fx/$t/run.sh"
        chmod +x "$fx/$t/run.sh"
    done
    cat >"$fx/a-tool/package.json" <<'JSON'
{ "peerDependencies": { "@tomgrv/scripts-b-tool": "*", "@tomgrv/scripts-zz-log": "*" } }
JSON
}

@test "zz-use resolves a local-origin script's peers from that same origin" {
    _local_fixture
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "$fx/a-tool"
    [ "$status" -eq 0 ]
    [[ "$("$bindir/b-tool")" == "fixture-b-tool" ]]
    [ -x "$bindir/zz-log" ]
    rm -rf "$fx" "$bindir"
}

@test "zz-use keeps a glob's origin for every match, even after peers resolve elsewhere" {
    _local_fixture
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env INSTALL_BIN_DIR="$bindir" PATH="/usr/bin:/bin" "$zz_use_bin" "$fx/*-tool"
    [ "$status" -eq 0 ]
    for t in a-tool b-tool c-tool; do
        [[ "$("$bindir/$t")" == "fixture-$t" ]]
    done
    rm -rf "$fx" "$bindir"
}

@test "zz-use skips a pinned re-request whose install stamp matches" {
    src=$(mktemp -d)
    mkdir -p "$src/repo-v1/some-tool"
    printf '#!/bin/sh\necho pinned\n' >"$src/repo-v1/some-tool/run.sh"
    tarball="$src/repo.tar.gz"
    tar -C "$src" -czf "$tarball" repo-v1
    cache=$(mktemp -d)
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env ZZ_USE_REPO_URL="file://$tarball" ZZ_CACHE_DIR="$cache" INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" someorg/repo/some-tool@v1
    [ "$status" -eq 0 ]
    [[ "$("$bindir/some-tool")" == "pinned" ]]
    run env ZZ_DEBUG=1 ZZ_USE_REPO_URL="file://$tarball" ZZ_CACHE_DIR="$cache" INSTALL_BIN_DIR="$bindir" PATH="$bindir:$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" someorg/repo/some-tool@v1
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed from"* ]]
    [[ "$output" != *"Installing"* ]]
    rm -rf "$src" "$cache" "$bindir"
}

# zz-log comes from $TEST_BIN here: these origins never resolve the
# default source that would otherwise put it on PATH.
_sha_payload() {
    payload=$(mktemp)
    printf '#!/bin/sh\necho downloaded\n' >"$payload"
}
_sha_config() {
    cfg=$(mktemp)
    printf '{"fake-dl-tool":{"url":"file://%s","archive":"raw","sha256":"%s"}}' "$payload" "$1" >"$cfg"
}

@test "zz-use installs a download whose sha256 matches" {
    _sha_payload
    _sha_config "$(sha256sum "$payload" | cut -d' ' -f1)"
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env ZZ_USE_CONFIG="$cfg" INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" fake-dl-tool
    [ "$status" -eq 0 ]
    [[ "$("$bindir/fake-dl-tool")" == "downloaded" ]]
    rm -rf "$payload" "$cfg" "$bindir"
}

@test "zz-use rejects a download whose sha256 doesn't match" {
    _sha_payload
    _sha_config 0000000000000000000000000000000000000000000000000000000000000000
    bindir=$(mktemp -d)
    zz_use_bin=$(command -v zz-use)
    run env ZZ_USE_CONFIG="$cfg" INSTALL_BIN_DIR="$bindir" PATH="$TEST_BIN:/usr/bin:/bin" "$zz_use_bin" fake-dl-tool
    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum mismatch"* ]]
    [ ! -e "$bindir/fake-dl-tool" ]
    rm -rf "$payload" "$cfg" "$bindir"
}
