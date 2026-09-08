#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path

    export REPO_DIR="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO_DIR"
    cd "$REPO_DIR"
    git config user.email "test@example.com"
    git config user.name "Test"

    mkdir -p src/pkg-a
    cat >package.json <<'EOF'
{
    "name": "root",
    "version": "1.0.0",
    "workspaces": ["src/*"],
    "bump-version": {
        "files": [
            {"filename": "composer.json", "type": "json"},
            {"filename": "package.json", "type": "json"},
            {"filename": "package.json", "type": "json@ws"},
            {"filename": "VERSION", "type": "plain-text"}
        ]
    }
}
EOF
    echo '{"name": "pkg-a", "version": "1.0.0"}' >src/pkg-a/package.json
    git add -A
    git commit -q -m "init"
    git tag v1.0.0
    echo "changed" >>src/pkg-a/package.json.marker
    git add -A
    git commit -q -m "touch pkg-a"
}

teardown() {
    teardown_scripts_path
}

@test "bump-version is on PATH and syntactically valid" {
    run bash -n "$(command -v bump-version)"
    [ "$status" -eq 0 ]
}

@test "bump-version updates the root file and warns about missing ones" {
    run bump-version --version 2.0.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated package.json to version 2.0.0"* ]]
    [[ "$output" == *"File not found: composer.json"* ]]
    [[ "$output" == *"File not found: VERSION"* ]]
    [ "$(jq -r .version package.json)" = "2.0.0" ]
}

@test "bump-version -m only bumps workspaces affected by the given range" {
    run bump-version -m -r "v1.0.0..HEAD" --version 2.0.0
    [ "$status" -eq 0 ]
    [ "$(jq -r .version src/pkg-a/package.json)" = "2.0.0" ]
}
