#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    # Isolate installs to $TEST_BIN instead of the real /usr/local/bin.
    export INSTALL_BIN_DIR="$TEST_BIN"
}

teardown() {
    teardown_scripts_path
}

stub_docker_available() {
    cat >"$TEST_BIN/docker" <<'EOF'
#!/bin/sh
case "$1" in
    info) exit 0 ;;
    run) shift; echo "docker run called with: $*" ;;
esac
EOF
    chmod +x "$TEST_BIN/docker"
}

stub_docker_unreachable() {
    # `docker` on PATH but its daemon isn't -- `docker info` fails, same as
    # a docker CLI with no docker-in-docker behind it.
    cat >"$TEST_BIN/docker" <<'EOF'
#!/bin/sh
case "$1" in
    info) exit 1 ;;
esac
EOF
    chmod +x "$TEST_BIN/docker"
}

stub_dotnet() {
    # Simulates `dotnet tool install ... --tool-path <dir>` by dropping a
    # dotnet-gitversion stub into whatever --tool-path it's given.
    cat >"$TEST_BIN/dotnet" <<'EOF'
#!/bin/sh
if [ "$1" = "tool" ] && [ "$2" = "install" ]; then
    dir=""
    prev=""
    for arg do
        [ "$prev" = "--tool-path" ] && dir="$arg"
        prev="$arg"
    done
    cat >"$dir/dotnet-gitversion" <<'INNER'
#!/bin/sh
echo "dotnet-gitversion called with: $*"
INNER
    chmod +x "$dir/dotnet-gitversion"
fi
EOF
    chmod +x "$TEST_BIN/dotnet"
}

@test "gv is on PATH and syntactically valid" {
    run bash -n "$(command -v gv)"
    [ "$status" -eq 0 ]
}

@test "gv prefers docker-gitversion when Docker's daemon is reachable, installing the wrapper if missing" {
    stub_docker_available
    run gv -showvariable SemVer
    [ "$status" -eq 0 ]
    [ -x "$TEST_BIN/docker-gitversion" ]
    [[ "$output" == *"docker run called with:"* ]]
    [[ "$output" == *"gittools/gitversion"* ]]
    [[ "$output" == *"-config .gitversion"* ]]
    [[ "$output" == *"-showvariable SemVer"* ]]
}

@test "gv reuses an already-installed docker-gitversion instead of recreating it" {
    stub_docker_available
    cat >"$TEST_BIN/docker-gitversion" <<'EOF'
#!/bin/sh
echo "existing docker-gitversion called with: $*"
EOF
    chmod +x "$TEST_BIN/docker-gitversion"
    run gv -showvariable SemVer
    [ "$status" -eq 0 ]
    [[ "$output" == *"existing docker-gitversion called with:"* ]]
}

@test "gv falls back to dotnet-gitversion when Docker's daemon is unreachable" {
    stub_docker_unreachable
    stub_dotnet
    run gv -showvariable SemVer
    [ "$status" -eq 0 ]
    [ -x "$TEST_BIN/dotnet-gitversion" ]
    [[ "$output" == *"dotnet-gitversion called with:"* ]]
    [[ "$output" == *"-config .gitversion"* ]]
    [[ "$output" == *"-showvariable SemVer"* ]]
}

@test "gv reuses an already-installed dotnet-gitversion instead of reinstalling it" {
    stub_docker_unreachable
    cat >"$TEST_BIN/dotnet-gitversion" <<'EOF'
#!/bin/sh
echo "existing dotnet-gitversion called with: $*"
EOF
    chmod +x "$TEST_BIN/dotnet-gitversion"
    cat >"$TEST_BIN/dotnet" <<'EOF'
#!/bin/sh
echo "dotnet tool install should not have been called" >&2
exit 1
EOF
    chmod +x "$TEST_BIN/dotnet"
    run gv -showvariable SemVer
    [ "$status" -eq 0 ]
    [[ "$output" == *"existing dotnet-gitversion called with:"* ]]
}

@test "gv errors clearly when neither docker nor dotnet is available" {
    stub_docker_unreachable
    run gv -showvariable SemVer
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not run GitVersion --"* ]]
}

@test "gv errors clearly (not silently) when the dotnet tool install itself fails" {
    stub_docker_unreachable
    cat >"$TEST_BIN/dotnet" <<'EOF'
#!/bin/sh
echo "simulated network failure" >&2
exit 1
EOF
    chmod +x "$TEST_BIN/dotnet"
    run gv -showvariable SemVer
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not run GitVersion --"* ]]
}
