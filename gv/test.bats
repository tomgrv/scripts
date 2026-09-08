#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    # gv.sh calls /usr/local/bin/docker-gitversion by hardcoded absolute
    # path (not resolved via PATH), so the stub must live there too.
    cat >/usr/local/bin/docker-gitversion <<'EOF'
#!/bin/sh
echo "docker-gitversion called with: $*"
EOF
    chmod +x /usr/local/bin/docker-gitversion
}

teardown() {
    teardown_scripts_path
    rm -f /usr/local/bin/docker-gitversion
}

@test "gv is on PATH and syntactically valid" {
    run bash -n "$(command -v gv)"
    [ "$status" -eq 0 ]
}

@test "gv forwards its own config flag plus all arguments to docker-gitversion" {
    run gv -showvariable SemVer
    [ "$status" -eq 0 ]
    [[ "$output" == *"-config .gitversion"* ]]
    [[ "$output" == *"-showvariable SemVer"* ]]
}
